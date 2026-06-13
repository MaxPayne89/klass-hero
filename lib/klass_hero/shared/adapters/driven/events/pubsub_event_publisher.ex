defmodule KlassHero.Shared.Adapters.Driven.Events.PubSubEventPublisher do
  @moduledoc """
  Phoenix.PubSub implementation of the ForPublishingEvents port.

  Topic convention: `{aggregate_type}:{event_type}`. Messages are broadcast as
  `{:domain_event, %DomainEvent{}}` and received via `handle_info/2`.
  """

  @behaviour KlassHero.Shared.Domain.Ports.ForPublishingEvents

  alias KlassHero.Shared.Adapters.Driven.Events.PubSubBroadcaster
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.Tracing.Context

  @impl true
  def publish(%DomainEvent{} = event) do
    topic = derive_topic(event)
    publish(event, topic)
  end

  @impl true
  def publish(%DomainEvent{} = event, topic) when is_binary(topic) do
    event = Context.inject_into_event(event)

    PubSubBroadcaster.broadcast(event, topic,
      config_key: :event_publisher,
      message_tag: :domain_event,
      log_label: "event",
      extra_metadata: [aggregate_id: event.aggregate_id]
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
  Builds a topic string. Format: `{aggregate_type}:{event_type}`. Use for subscribing to specific event topics.
  """
  @spec build_topic(atom(), atom()) :: String.t()
  def build_topic(aggregate_type, event_type) do
    "#{aggregate_type}:#{event_type}"
  end

  @doc false
  @spec derive_topic(DomainEvent.t()) :: String.t()
  def derive_topic(%DomainEvent{aggregate_type: agg_type, event_type: event_type}) do
    build_topic(agg_type, event_type)
  end
end
