defmodule KlassHero.Shared.Tracing.Context do
  @moduledoc """
  Trace context propagation across process boundaries.

  Provides helpers to serialize/deserialize W3C Trace Context
  into event metadata maps and Oban job args. Uses
  `:otel_propagator_text_map` under the hood.

  ## Process boundaries requiring propagation

  1. **Integration events** — PubSub messages cross processes
  2. **Oban workers** — jobs execute in new processes

  Domain events dispatch synchronously in the caller's process
  and do NOT need explicit propagation.
  """

  require Logger

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
    # W3C Trace Context keys are always binary strings. Filter out any atom-keyed
    # entries (e.g. :correlation_id from event metadata) before handing to the
    # Erlang propagator, which expects {binary(), binary()} 2-tuples.
    headers = Enum.filter(context, fn {k, _} -> is_binary(k) end)

    if headers == [] do
      Logger.debug("[Tracing.Context] No binary keys in context map, skipping attach: #{inspect(Map.keys(context))}")
    else
      # extract/1 both deserializes the W3C Trace Context headers and attaches
      # the resulting context to the current process, returning the old token.
      :otel_propagator_text_map.extract(headers)
    end

    :ok
  end

  def attach(_empty), do: :ok

  @spec inject_into_event(struct()) :: struct()
  def inject_into_event(%{metadata: metadata} = event) do
    trace_context = inject()
    %{event | metadata: Map.merge(metadata, trace_context)}
  end

  @spec attach_from_event(struct()) :: :ok
  def attach_from_event(%{metadata: metadata}) do
    attach(metadata)
  end

  def attach_from_event(_event), do: :ok

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
