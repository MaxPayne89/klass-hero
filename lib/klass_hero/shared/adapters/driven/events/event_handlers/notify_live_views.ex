defmodule KlassHero.Shared.Adapters.Driven.Events.EventHandlers.NotifyLiveViews do
  @moduledoc """
  Generic handler that routes domain events to PubSub topics for LiveView real-time updates.

  Default topic derivation: `"\#{aggregate_type}:\#{event_type}"`.
  Contexts with simple topic needs (Enrollment, Participation) delegate directly.
  Contexts with custom routing (Messaging) reuse `safe_publish/2` only.

  ## Error strategy

  Swallows publish failures — the use case has already committed.
  PubSub delivery is best-effort notification to connected LiveViews.
  """

  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.EventPublishing

  require Logger

  @doc "Handles a domain event by publishing it to the derived PubSub topic."
  @spec handle(DomainEvent.t()) :: :ok
  def handle(%DomainEvent{} = event) do
    topic = derive_topic(event)
    safe_publish(event, topic)
  end

  @doc "Derives a PubSub topic from a domain event's aggregate_type and event_type."
  @spec derive_topic(DomainEvent.t()) :: String.t()
  def derive_topic(%DomainEvent{aggregate_type: agg, event_type: evt}) do
    build_topic(agg, evt)
  end

  @doc "Builds a PubSub topic string from aggregate type and event type atoms."
  @spec build_topic(atom(), atom()) :: String.t()
  def build_topic(aggregate_type, event_type) do
    "#{aggregate_type}:#{event_type}"
  end

  @doc """
  Publishes an event to a topic, swallowing failures with a warning log.

  Returns `:ok` regardless of outcome — PubSub is best-effort after commit.
  """
  @spec safe_publish(DomainEvent.t(), String.t()) :: :ok
  def safe_publish(event, topic) do
    case EventPublishing.publish(event, topic) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to publish #{event.event_type} to #{topic}",
          event_type: event.event_type,
          topic: topic,
          reason: inspect(reason)
        )

        :ok
    end
  end
end
