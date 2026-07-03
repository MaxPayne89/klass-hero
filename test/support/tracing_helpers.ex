defmodule KlassHero.TracingHelpers do
  @moduledoc """
  Test utilities for asserting on OpenTelemetry spans.

  ## Usage

  In your test module:

      use KlassHero.TracingHelpers

  This adds a setup block that configures OTel to send spans to the
  test process. Use `assert_span/1` and `assert_span/2` to verify spans.
  """

  require Record

  @span_fields Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl")
  Record.defrecord(:span, @span_fields)

  @status_fields Record.extract(:status, from_lib: "opentelemetry_api/include/opentelemetry.hrl")
  Record.defrecord(:status, @status_fields)

  defmacro __using__(_opts) do
    quote do
      import KlassHero.TracingHelpers

      setup do
        :otel_batch_processor.set_exporter(:otel_exporter_pid, self())
        :ok
      end
    end
  end

  @doc """
  Flushes the OTel batch processor so all completed spans are exported.
  Call this after code-under-test and before assertions.
  """
  def flush_spans do
    :otel_tracer_provider.force_flush()
  end

  @doc """
  Asserts a span with the given name was exported.
  Returns the full span record for further inspection.
  """
  defmacro assert_span(expected_name) do
    quote do
      KlassHero.TracingHelpers.flush_spans()

      assert_receive {:span, KlassHero.TracingHelpers.span(name: name) = received_span}
                     when name == unquote(expected_name),
                     1000

      received_span
    end
  end

  @doc """
  Asserts a span with the given name was exported and verifies attributes.
  `expected_attrs` is a keyword list of `{key, value}` pairs to check.
  """
  defmacro assert_span(expected_name, expected_attrs) do
    quote do
      received_span = assert_span(unquote(expected_name))
      attrs = span_attributes(received_span)

      for {key, value} <- unquote(expected_attrs) do
        # OTel stores attribute keys as strings; keyword lists produce atom keys.
        # Look up both forms to support either convention.
        string_key = to_string(key)

        actual =
          case Map.fetch(attrs, key) do
            {:ok, v} -> v
            :error -> Map.get(attrs, string_key)
          end

        assert actual == value,
               "Expected span attribute #{inspect(key)} to be #{inspect(value)}, " <>
                 "got #{inspect(actual)}"
      end

      received_span
    end
  end

  @doc """
  Asserts no span with the given name was exported.
  """
  defmacro refute_span(expected_name) do
    quote do
      KlassHero.TracingHelpers.flush_spans()

      # Match the name literally in the record pattern rather than via a `when`
      # guard — Elixir 1.20.2's `refute_receive` rejects a remote `==` guard here.
      refute_receive {:span, KlassHero.TracingHelpers.span(name: unquote(expected_name))}, 100
    end
  end

  @doc """
  Extracts attributes from a span record as a map of `%{key => value}`.
  """
  def span_attributes(span_record) do
    span_record
    |> span(:attributes)
    |> :otel_attributes.map()
  end

  @doc """
  Returns the status code from a span record (`:error`, `:ok`, or `:unset`).
  """
  def span_status_code(span_record) do
    span_record |> span(:status) |> status(:code)
  end
end
