defmodule KlassHero.Shared.Tracing.EctoSpanBridge do
  @moduledoc """
  Bridges Ecto query telemetry to OpenTelemetry child spans.

  The flattened contexts call `Repo` directly inside a `context_span`, so there
  is no driven-adapter seam to wrap each query in `db_interaction`. Instead, this
  handler listens on `[:klass_hero, :repo, :query]` and, for every query that
  runs **while a span is current**, emits a retroactive child span — turning the
  coarse context span into a trace with per-query detail, with zero call-site
  noise.

  Two deliberate properties:

  - **Child-only.** A query with no enclosing span emits nothing (no orphan-root
    `*.query` spans cluttering traces). The span is detail under an intent span,
    never a top-level entry on its own.
  - **PII default-deny.** Only the *parameterised* statement (`… WHERE id = $1`)
    and bounded timings travel to the span. Param **values** are dropped — they
    never leave the process.

  Attached once at boot from `KlassHeroWeb.Telemetry.init/1`.
  """

  @handler_id "klass-hero-ecto-span-bridge"
  @event [:klass_hero, :repo, :query]

  @doc "Attaches the telemetry handler. Idempotent across boots in a single VM."
  def attach do
    :telemetry.attach(@handler_id, @event, &__MODULE__.handle_event/4, %{})
  end

  @doc false
  def handle_event(_event, measurements, metadata, _config) do
    case OpenTelemetry.Tracer.current_span_ctx() do
      :undefined -> :ok
      _parent -> emit_span(measurements, metadata)
    end
  end

  defp emit_span(measurements, metadata) do
    end_time = :opentelemetry.timestamp()
    start_time = end_time - Map.get(measurements, :total_time, 0)
    source = metadata[:source] || "query"
    tracer = :opentelemetry.get_application_tracer(__MODULE__)

    span_ctx =
      :otel_tracer.start_span(:otel_ctx.get_current(), tracer, "#{source}.query", %{start_time: start_time})

    OpenTelemetry.Span.set_attributes(span_ctx, attributes(measurements, metadata, source))
    set_status(span_ctx, metadata[:result])
    OpenTelemetry.Span.end_span(span_ctx, end_time)
    :ok
  end

  defp attributes(measurements, metadata, source) do
    %{
      "db.system" => "postgresql",
      "db.source" => source,
      "db.statement" => metadata[:query],
      "db.total_time_ms" => to_ms(measurements[:total_time]),
      "db.query_time_ms" => to_ms(measurements[:query_time]),
      "db.queue_time_ms" => to_ms(measurements[:queue_time]),
      "db.decode_time_ms" => to_ms(measurements[:decode_time]),
      "db.rows" => row_count(metadata[:result])
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp to_ms(nil), do: nil
  defp to_ms(native), do: System.convert_time_unit(native, :native, :microsecond) / 1000

  defp row_count({:ok, %{num_rows: rows}}), do: rows
  defp row_count(_result), do: nil

  defp set_status(span_ctx, {:error, _reason}),
    do: OpenTelemetry.Span.set_status(span_ctx, OpenTelemetry.status(:error, "query_error"))

  defp set_status(_span_ctx, _result), do: :ok
end
