defmodule KlassHero.Shared.Tracing.Context do
  @moduledoc """
  Trace context propagation across the one process boundary that has one.

  Serializes W3C Trace Context into Oban job args and restores it in the worker
  process, over `:otel_propagator_text_map`.

  Oban is the only boundary that needs this. An integration event crosses process
  boundaries *as* job args — ADR-0014 replaced the PubSub delivery path with a single
  `EventDeliveryWorker` job, so an event's trace context is its job's trace context.
  A same-context reaction runs inside the producer's own process and needs no
  propagation at all.

  Propagating per-event instead was tried and removed in #1358: `TracedWorker` attaches
  the job's context before opening the worker span, so a second attach inside that span
  — once per event, with no restore token — would reparent later consumers' spans to an
  earlier event's producer.
  """

  @trace_context_key "trace_context"

  @spec inject() :: map()
  def inject do
    case :otel_propagator_text_map.inject([]) do
      [] -> %{}
      headers -> Map.new(headers)
    end
  end

  @spec attach(map()) :: :ok
  def attach(context) when is_map(context) and map_size(context) > 0 do
    # extract/1 both deserializes the W3C Trace Context headers and attaches
    # the resulting context to the current process, returning the old token.
    :otel_propagator_text_map.extract(Map.to_list(context))

    :ok
  end

  def attach(_empty), do: :ok

  @spec inject_into_args(map()) :: map()
  def inject_into_args(args) when is_map(args) do
    case inject() do
      empty when map_size(empty) == 0 -> args
      context -> Map.put(args, @trace_context_key, context)
    end
  end

  @spec attach_from_args(map()) :: :ok
  def attach_from_args(%{@trace_context_key => context}) when is_map(context) do
    attach(context)
  end

  def attach_from_args(_args), do: :ok
end
