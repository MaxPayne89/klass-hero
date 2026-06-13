defmodule KlassHero.Messaging.Adapters.Driving.Events.EventHandlers.NotifyLiveViews do
  @moduledoc """
  Routes Messaging domain events to PubSub topics for LiveView real-time updates.

  Registered on the Messaging DomainEventBus. Each `handle/1` clause derives the
  correct topic from the event payload and publishes via the configured event
  publisher (PubSub in prod, TestEventPublisher in tests).

  ## Error strategy

  Swallows publish failures — the originating use case has already committed its
  transaction. PubSub delivery is best-effort notification to connected LiveViews.

  ## Topic routing

  - `:message_sent`           → `"conversation:{id}"`
  - `:messages_read`          → `"conversation:{id}"`
  - `:conversation_created`   → `"user:{id}:messages"` per participant (fan-out)
  - `:conversations_archived` → `"messaging:bulk_operations"`
  - `:retention_enforced`     → `"messaging:bulk_operations"`
  """

  alias KlassHero.Shared.Adapters.Driven.Events.EventHandlers.NotifyLiveViews,
    as: SharedNotifyLiveViews

  alias KlassHero.Shared.Domain.Events.DomainEvent

  @bulk_topic "messaging:bulk_operations"

  @doc """
  Handles a domain event by publishing it to the appropriate PubSub topic.
  """
  @spec handle(DomainEvent.t()) :: :ok

  def handle(%DomainEvent{event_type: :message_sent} = event) do
    topic = conversation_topic(event.payload.conversation_id)
    SharedNotifyLiveViews.safe_publish(event, topic)
  end

  def handle(%DomainEvent{event_type: :messages_read} = event) do
    topic = conversation_topic(event.payload.conversation_id)
    SharedNotifyLiveViews.safe_publish(event, topic)
  end

  def handle(%DomainEvent{event_type: :conversation_created} = event) do
    Enum.each(event.payload.participant_ids, fn user_id ->
      topic = user_messages_topic(user_id)
      SharedNotifyLiveViews.safe_publish(event, topic)
    end)

    :ok
  end

  def handle(%DomainEvent{event_type: :conversations_archived} = event) do
    SharedNotifyLiveViews.safe_publish(event, @bulk_topic)
  end

  def handle(%DomainEvent{event_type: :retention_enforced} = event) do
    SharedNotifyLiveViews.safe_publish(event, @bulk_topic)
  end

  @doc "Returns PubSub topic for a specific conversation."
  def conversation_topic(conversation_id), do: "conversation:#{conversation_id}"

  @doc "Returns PubSub topic for a user's message updates."
  def user_messages_topic(user_id), do: "user:#{user_id}:messages"
end
