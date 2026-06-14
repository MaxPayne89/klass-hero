defmodule KlassHero.Shared.Interaction do
  @moduledoc """
  A uniform observability envelope for outbound driven-adapter I/O.

  Adapters wrap a single outbound call in an `interaction`/`db_interaction`/...
  block. The macro builds an `Interaction` carrier around the block, opens an
  OpenTelemetry span (via `KlassHero.Shared.Tracing.span`), emits `:telemetry`
  metrics, classifies the outcome, normalises the error, and captures a
  PII-sanitised view of the inputs — then returns the block's **native value
  unchanged**.

  The carrier is an internal pipeline value: it never reaches the caller, so
  port contracts and call sites are untouched. Exceptions are observed on both
  the span and telemetry, then reraised — let-it-crash is preserved.

  ## Usage

      defmodule MyRepository do
        use KlassHero.Shared.Interaction

        def create(attrs) do
          db_interaction operation: :create, entity: "enrollment" do
            %Schema{} |> Schema.changeset(attrs) |> Repo.insert()
          end
        end
      end

  ## Options

  - `:kind` — required on the generic `interaction/2`; pre-filled by the sugar
    macros (`db_interaction`, `http_interaction`, ...).
  - `:operation` — low-cardinality verb for span + metric grouping (`:create`).
  - `:success` — optional `(result -> boolean)` that overrides the kind's
    default classification, for return shapes the kind can't reason about.
  - `:input` — an expression whose value is captured and passed to the kind's
    `sanitize/2`. Never emitted raw; only the sanitised form leaves the process.
  - `:capture` — forwarded to `sanitize/2` to opt into an allowlist
    (default: drop everything to `:redacted`).
  - Remaining keys (`:entity`, `:service`, ...) are forwarded to the kind's
    `attributes/2`.
  """

  alias KlassHero.Shared.Interaction.Kind
  alias KlassHero.Shared.Tracing

  @kinds %{
    db: Kind.Db,
    http: Kind.Http,
    s3: Kind.S3,
    email: Kind.Email,
    feature_flags: Kind.FeatureFlags
  }

  @enforce_keys [:kind, :adapter]
  defstruct [
    :kind,
    :operation,
    :adapter,
    :function,
    :input,
    :sanitized_input,
    :result,
    :status,
    :error,
    :duration_us,
    :metadata
  ]

  @type t :: %__MODULE__{
          kind: atom(),
          operation: atom() | String.t() | nil,
          adapter: module(),
          function: {atom(), arity()} | nil,
          input: term(),
          sanitized_input: term(),
          result: term(),
          status: Kind.status() | nil,
          error: term() | nil,
          duration_us: non_neg_integer() | nil,
          metadata: map()
        }

  defmacro __using__(_opts) do
    quote do
      use Tracing

      import KlassHero.Shared.Interaction,
        only: [
          interaction: 2,
          db_interaction: 2,
          http_interaction: 2,
          s3_interaction: 2,
          email_interaction: 2,
          feature_flags_interaction: 2
        ]

      alias KlassHero.Shared.Interaction

      require Interaction
    end
  end

  @doc """
  Wraps a block as an interaction of the kind given by `:kind`.

  Prefer the per-kind sugar macros below; reach for this only when the kind is
  computed or unusual.
  """
  defmacro interaction(opts, do: block), do: build(opts, block, __CALLER__)

  @doc "Sugar for `interaction kind: :db, ...`."
  defmacro db_interaction(opts, do: block),
    do: build([{:kind, :db} | opts], block, __CALLER__)

  @doc "Sugar for `interaction kind: :http, ...`."
  defmacro http_interaction(opts, do: block),
    do: build([{:kind, :http} | opts], block, __CALLER__)

  @doc "Sugar for `interaction kind: :s3, ...`."
  defmacro s3_interaction(opts, do: block),
    do: build([{:kind, :s3} | opts], block, __CALLER__)

  @doc "Sugar for `interaction kind: :email, ...`."
  defmacro email_interaction(opts, do: block),
    do: build([{:kind, :email} | opts], block, __CALLER__)

  @doc "Sugar for `interaction kind: :feature_flags, ...`."
  defmacro feature_flags_interaction(opts, do: block),
    do: build([{:kind, :feature_flags} | opts], block, __CALLER__)

  defp build(opts, block, caller) do
    kind = Keyword.fetch!(opts, :kind)
    kind_mod = Map.fetch!(@kinds, kind)
    operation = Keyword.get(opts, :operation)
    success = Keyword.get(opts, :success)
    input_ast = Keyword.get(opts, :input)
    kind_opts = Keyword.drop(opts, [:kind, :success, :input])

    span_name = Tracing.gen_span_name(caller)
    adapter = caller.module
    {fun_name, arity} = caller.function

    quote do
      success_fun = unquote(success)
      input = unquote(input_ast)
      kind_opts = unquote(kind_opts)
      kind_mod = unquote(kind_mod)

      Tracing.span unquote(span_name) do
        :telemetry.span(
          [:klass_hero, :interaction],
          %{
            io_kind: unquote(kind),
            operation: unquote(operation),
            adapter: unquote(adapter)
          },
          fn ->
            start_us = System.monotonic_time(:microsecond)
            result = unquote(block)
            duration_us = System.monotonic_time(:microsecond) - start_us

            status = KlassHero.Shared.Interaction.classify(result, kind_mod, success_fun)
            attributes = kind_mod.attributes(result, kind_opts)

            interaction = %KlassHero.Shared.Interaction{
              kind: unquote(kind),
              operation: unquote(operation),
              adapter: unquote(adapter),
              function: {unquote(fun_name), unquote(arity)},
              input: input,
              sanitized_input: kind_mod.sanitize(input, kind_opts),
              result: result,
              status: status,
              error: if(status == :error, do: kind_mod.normalize_error(result)),
              duration_us: duration_us,
              metadata: attributes
            }

            KlassHero.Shared.Interaction.set_span_attributes(attributes)

            {result, %{duration_us: duration_us}, KlassHero.Shared.Interaction.to_telemetry_metadata(interaction)}
          end
        )
      end
    end
  end

  @doc """
  Resolves the interaction status from the block result.

  With no `success:` classifier, defers to the kind's `classify/1`. With one,
  the classifier fully decides — `true` is `:ok`, `false` is `:error`.
  """
  @spec classify(Kind.result(), module(), (Kind.result() -> boolean()) | nil) :: Kind.status()
  def classify(result, kind_mod, nil), do: kind_mod.classify(result)

  def classify(result, _kind_mod, fun) when is_function(fun, 1) do
    if fun.(result), do: :ok, else: :error
  end

  @doc """
  Projects the carrier onto telemetry metadata.

  Deliberately omits `:input` and `:result` (raw, possibly PII or large); only
  the sanitised input and bounded attributes travel to handlers. `:kind` is
  emitted as `:io_kind` to avoid clashing with the `:kind` (error class) that
  `:telemetry.span` injects on its `[:exception]` event.
  """
  @spec to_telemetry_metadata(t()) :: map()
  def to_telemetry_metadata(%__MODULE__{} = interaction) do
    %{
      io_kind: interaction.kind,
      operation: interaction.operation,
      adapter: interaction.adapter,
      status: interaction.status,
      error: interaction.error,
      sanitized_input: interaction.sanitized_input,
      attributes: interaction.metadata
    }
  end

  @doc """
  Mirrors already-namespaced attributes onto the current OTel span.

  Skips `nil` values. Called inside the live span, so it targets the span the
  enclosing `Tracing.span` opened.
  """
  @spec set_span_attributes(map()) :: :ok
  def set_span_attributes(attributes) do
    Enum.each(attributes, fn
      {_key, nil} -> :ok
      {key, value} -> Tracing.set_attribute(key, value)
    end)
  end
end
