defmodule KlassHero.Shared.Adapters.Driven.Events.PubSubIntegrationEventPublisher do
  @moduledoc """
  Phoenix.PubSub implementation of the ForPublishingIntegrationEvents port.

  Topic convention: `integration:{source_context}:{event_type}`. Messages are broadcast as
  `{:integration_event, %IntegrationEvent{}}` and received via `handle_info/2`.
  Also enqueues one `CriticalEventWorker` Oban job per registered handler for critical events.
  """

  @behaviour KlassHero.Shared.Domain.Ports.ForPublishingIntegrationEvents

  alias KlassHero.Shared.Adapters.Driven.Events.CriticalEventHandlerRegistry
  alias KlassHero.Shared.Adapters.Driven.Events.CriticalEventSerializer
  alias KlassHero.Shared.Adapters.Driven.Events.PubSubBroadcaster
  alias KlassHero.Shared.Adapters.Driven.Workers.CriticalEventWorker
  alias KlassHero.Shared.Domain.Events.IntegrationEvent
  alias KlassHero.Shared.Domain.Services.CriticalEventDispatcher
  alias KlassHero.Shared.Tracing.Context

  require Logger

  @impl true
  def publish(%IntegrationEvent{} = event) do
    topic = derive_topic(event)

    case publish(event, topic) do
      :ok ->
        maybe_enqueue_critical_jobs(event, topic)
        :ok

      error ->
        error
    end
  end

  @impl true
  def publish(%IntegrationEvent{} = event, topic) when is_binary(topic) do
    event = Context.inject_into_event(event)

    PubSubBroadcaster.broadcast(event, topic,
      config_key: :integration_event_publisher,
      message_tag: :integration_event,
      log_label: "integration event",
      extra_metadata: [entity_id: event.entity_id]
    )
  end

  @impl true
  def publish_all(events) when is_list(events) do
    results = Enum.map(events, &publish/1)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> :ok
      error -> error
    end
  end

  @doc """
  Builds a topic string. Format: `integration:{source_context}:{event_type}`.
  """
  @spec build_topic(atom(), atom()) :: String.t()
  def build_topic(source_context, event_type) do
    "integration:#{source_context}:#{event_type}"
  end

  @doc false
  @spec derive_topic(IntegrationEvent.t()) :: String.t()
  def derive_topic(%IntegrationEvent{source_context: ctx, event_type: event_type}) do
    build_topic(ctx, event_type)
  end

  # PubSub is fire-and-forget — enqueue one Oban job per handler for durable retry if PubSub fails.
  defp maybe_enqueue_critical_jobs(%IntegrationEvent{} = event, topic) do
    if IntegrationEvent.critical?(event) do
      handlers = CriticalEventHandlerRegistry.handlers_for(topic)

      Enum.each(handlers, fn {_module, _function} = handler_tuple ->
        handler_ref = CriticalEventDispatcher.handler_ref(handler_tuple)

        args =
          CriticalEventSerializer.serialize(event)
          |> Map.put("handler", handler_ref)

        enqueue_critical_job(args, event, handler_ref)
      end)
    end
  end

  defp enqueue_critical_job(args, event, handler_ref) do
    args = Context.inject_into_args(args)

    case CriticalEventWorker.insert_job(args) do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        # PubSub already delivered, but durable fallback is now absent — alert operators.
        Logger.error(
          "Failed to enqueue durable delivery job for critical integration event " <>
            "#{event.event_type} (#{event.event_id}), handler #{handler_ref}. " <>
            "Durable delivery guarantee voided for this handler.",
          event_id: event.event_id,
          event_type: event.event_type,
          handler: handler_ref,
          reason: inspect(reason)
        )
    end
  end
end
