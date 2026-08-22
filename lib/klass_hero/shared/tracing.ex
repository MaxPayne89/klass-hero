defmodule KlassHero.Shared.Tracing do
  @moduledoc """
  Central tracing abstraction for deliberate, adapter-only observability.

  Provides a `span` macro that wraps OpenTelemetry span creation with:
  - Automatic span naming from module + function + arity at compile time
  - Exception capture, recording, and reraise
  - Attribute helpers that preserve numeric types

  ## Usage

      defmodule MyRepository do
        use KlassHero.Shared.Tracing

        def create(attrs) do
          span do
            set_attribute("db.operation", "insert")
            # ... existing code
          end
        end
      end

  """

  # Module-name segments stripped before a span is named, so a span reads
  # `Provider.ProviderPrograms.handle_event/2` rather than repeating the tree.
  #
  # This list is scaffolding for the nested context layout and should shrink
  # with it — but only once *every* context is flat. While contexts still carry
  # `Adapters.Driven.Projections.*` and friends in their module names, pruning
  # an entry here silently renames live production spans (#1259).
  @noise_segments ~w[
    Elixir KlassHero Adapters Driven Driving Persistence Repositories
    Schemas Mappers Queries Events EventHandlers Workers Projections
  ]

  defmacro __using__(_opts) do
    quote do
      import KlassHero.Shared.Tracing,
        only: [
          span: 1,
          span: 2,
          acl_span: 2,
          context_span: 1,
          context_span: 2,
          set_attribute: 2,
          set_attributes: 2
        ]

      alias KlassHero.Shared.Tracing

      require OpenTelemetry.Tracer
      require Tracing
    end
  end

  @doc """
  Creates a span around the given block.

  When called without a name, derives the span name from the calling
  module + function + arity at compile time.

  Wraps the block in `try/rescue` — on exception, records the error
  on the span and reraises. The outer `with_span` ensures the span is
  always ended and collected.
  """
  defmacro span(name \\ nil, do: block) do
    span_name = name || gen_span_name(__CALLER__)

    quote do
      tracer = :opentelemetry.get_application_tracer(__MODULE__)

      :otel_tracer.with_span(tracer, unquote(span_name), %{}, fn _ctx ->
        try do
          unquote(block)
        rescue
          exception ->
            OpenTelemetry.Tracer.set_attribute("exception.type", inspect(exception.__struct__))
            OpenTelemetry.Tracer.set_attribute("exception.message", Exception.message(exception))

            OpenTelemetry.Tracer.set_attribute(
              "exception.stacktrace",
              Exception.format_stacktrace(__STACKTRACE__)
            )

            OpenTelemetry.Tracer.set_status(:error, "exception")

            reraise exception, __STACKTRACE__
        end
      end)
    end
  end

  @doc """
  Wraps an ACL adapter function body in a span tagged with the standard
  `acl.{source,target,operation}` attributes.

  `source` and `target` name the bounded contexts being bridged. `operation` is
  derived from the calling function name at compile time, so all callers stay
  consistent:

      def get_children_by_ids(ids) do
        acl_span source: "enrollment", target: "family" do
          # implementation
        end
      end

  Expands in the caller (like `span/2`) so span and operation attribution point
  at the adapter function, not this module.
  """
  defmacro acl_span(opts, do: block) do
    {function, _arity} = __CALLER__.function
    operation = Atom.to_string(function)
    source = Keyword.fetch!(opts, :source)
    target = Keyword.fetch!(opts, :target)

    quote do
      span do
        set_attributes("acl",
          source: unquote(source),
          target: unquote(target),
          operation: unquote(operation)
        )

        unquote(block)
      end
    end
  end

  @doc """
  Wraps a public context function body in a span tagged with the standard
  `context.{name,operation}` attributes.

  `name` is the bounded context the calling module belongs to — the segment after
  `KlassHero`, so `KlassHero.Family` → `"Family"` and `KlassHero.Provider.Staff` →
  `"Provider"`, not `"Staff"`. `operation` is the calling function name. Both are
  resolved at compile time.

  This is the coarse, semantic seam for the flattened contexts: one span per
  business operation, under which fine-grained DB spans (bridged from Ecto
  telemetry) nest automatically.

      def create_child(attrs) do
        context_span entity: "child" do
          # Multi insert + event dispatch
        end
      end

  Extra opts are forwarded as additional `context.*` attributes. Expands in the
  caller (like `span/2`), so the span name points at the context function.
  """
  defmacro context_span(do: block), do: build_context_span([], block, __CALLER__)
  defmacro context_span(opts, do: block), do: build_context_span(opts, block, __CALLER__)

  defp build_context_span(opts, block, caller) do
    {function, _arity} = caller.function
    operation = Atom.to_string(function)
    name = context_name(caller.module)

    quote do
      span do
        set_attributes(
          "context",
          [name: unquote(name), operation: unquote(operation)] ++ unquote(opts)
        )

        unquote(block)
      end
    end
  end

  # The bounded context, not the module's own last segment. Provider is built
  # from `defdelegate`, so all 26 of its spans are emitted from submodules and
  # reported `Staff`/`Profiles`/`Assignments` — `Provider` never appeared in
  # production at all, and no context-level trigger could be written for it
  # (#1424). Every other context calls `context_span` from its facade, where the
  # two rules coincide, which is why this went unnoticed.
  defp context_name(module) do
    case Module.split(module) do
      ["KlassHero", context | _] -> context
      segments -> List.last(segments)
    end
  end

  @doc """
  Sets a single attribute on the current span.

  Preserves numeric and boolean types. Atoms are converted to strings.
  Complex types (maps, lists, structs) are converted via `inspect/1`.
  """
  def set_attribute(key, value) when is_binary(key) do
    OpenTelemetry.Tracer.set_attribute(key, normalize_value(value))
  end

  @doc """
  Sets multiple attributes on the current span from a keyword list or map.

  Each key is prefixed with the given namespace: `set_attributes("db", operation: "insert")`
  sets `"db.operation" => "insert"`.
  """
  def set_attributes(namespace, enumerable) when is_binary(namespace) do
    Enum.each(enumerable, fn {key, value} ->
      set_attribute("#{namespace}.#{key}", value)
    end)
  end

  defp normalize_value(value) when is_binary(value), do: value
  defp normalize_value(value) when is_integer(value), do: value
  defp normalize_value(value) when is_float(value), do: value
  defp normalize_value(value) when is_boolean(value), do: value
  defp normalize_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_value(value), do: inspect(value)

  @doc false
  def gen_span_name(caller) do
    {function, arity} = caller.function

    module_name =
      caller.module
      |> Module.split()
      |> Enum.reject(&(&1 in @noise_segments))
      |> Enum.join(".")

    "#{module_name}.#{function}/#{arity}"
  end

  @doc false
  def gen_span_name_for_worker(module) do
    module_name =
      module
      |> Module.split()
      |> Enum.reject(&(&1 in @noise_segments))
      |> Enum.join(".")

    "#{module_name}.execute/1"
  end
end
