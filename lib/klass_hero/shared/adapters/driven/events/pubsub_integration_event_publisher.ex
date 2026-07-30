defmodule KlassHero.Shared.Adapters.Driven.Events.PubSubIntegrationEventPublisher do
  @moduledoc """
  Phoenix.PubSub implementation of the ForPublishingIntegrationEvents port.

  Topic convention: `integration:{source_context}:{event_type}`. Messages are broadcast as
  `{:integration_event, %IntegrationEvent{}}` and received via `handle_info/2`.

  Since the outbox took over delivery, this carries LiveView notifications and nothing
  else — every consumer that owns persistent state is called by the delivery job. A
  dropped broadcast now costs a stale UI until the next render, not a lost event.
  """

  @behaviour KlassHero.Shared.ForPublishingIntegrationEvents

  alias KlassHero.Shared.Adapters.Driven.Events.PubSubBroadcaster
  alias KlassHero.Shared.Domain.Events.IntegrationEvent
  alias KlassHero.Shared.Tracing.Context

  @impl true
  def publish(%IntegrationEvent{} = event), do: publish(event, derive_topic(event))

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
end
