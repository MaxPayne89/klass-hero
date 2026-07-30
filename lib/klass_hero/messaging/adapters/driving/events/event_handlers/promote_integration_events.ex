defmodule KlassHero.Messaging.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents do
  @moduledoc """
  Maps Messaging domain events to their integration events.

  `promote/1` is pure — `KlassHero.Shared.Outbox` calls it inside the producer's
  transaction so the integration event exists before anything commits. Returning
  `nil` for an unmapped event type reproduces today's semantics exactly: an event
  with no registration was never promoted either.

  Note `:user_data_anonymized` promotes to `:message_data_anonymized` — the one
  place in this module where the two names differ.

  `handle/1` is the bus-registered wrapper that promotes and publishes; it goes
  when this context's producers move to the outbox.

  ## Error strategy

  On the bus path, critical events (`:conversation_created`, `:message_sent`,
  `:participant_added`, `:participant_removed`) propagate publish failures to the
  calling use case and the rest swallow them. The outbox replaces both with Oban
  retry.
  """

  alias KlassHero.Messaging.Domain.Events.MessagingIntegrationEvents
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.Domain.Events.IntegrationEvent
  alias KlassHero.Shared.IntegrationEventPublishing

  @spec promote(DomainEvent.t()) :: IntegrationEvent.t() | nil
  def promote(%DomainEvent{event_type: :user_data_anonymized} = event) do
    MessagingIntegrationEvents.message_data_anonymized(event.payload.user_id)
  end

  def promote(%DomainEvent{event_type: :conversation_created} = event) do
    MessagingIntegrationEvents.conversation_created(event.aggregate_id, event.payload)
  end

  def promote(%DomainEvent{event_type: :message_sent} = event) do
    MessagingIntegrationEvents.message_sent(event.aggregate_id, event.payload)
  end

  def promote(%DomainEvent{event_type: :messages_read} = event) do
    MessagingIntegrationEvents.messages_read(event.aggregate_id, event.payload)
  end

  def promote(%DomainEvent{event_type: :conversation_archived} = event) do
    MessagingIntegrationEvents.conversation_archived(event.aggregate_id, event.payload)
  end

  def promote(%DomainEvent{event_type: :conversations_archived} = event) do
    MessagingIntegrationEvents.conversations_archived(event.aggregate_id, event.payload)
  end

  def promote(%DomainEvent{event_type: :participant_added} = event) do
    MessagingIntegrationEvents.participant_added(event.aggregate_id, event.payload)
  end

  def promote(%DomainEvent{event_type: :participant_removed} = event) do
    MessagingIntegrationEvents.participant_removed(event.aggregate_id, event.payload)
  end

  def promote(%DomainEvent{}), do: nil

  @doc """
  Handles a domain event by promoting it to the corresponding integration event.
  """
  @spec handle(DomainEvent.t()) :: :ok | {:error, term()}
  def handle(%DomainEvent{event_type: :user_data_anonymized} = event) do
    event
    |> promote()
    |> IntegrationEventPublishing.publish_best_effort("message_data_anonymized",
      user_id: event.payload.user_id
    )
  end

  def handle(%DomainEvent{event_type: :conversation_created} = event) do
    event
    |> promote()
    |> IntegrationEventPublishing.publish_critical("conversation_created",
      conversation_id: event.aggregate_id
    )
  end

  def handle(%DomainEvent{event_type: :message_sent} = event) do
    event
    |> promote()
    |> IntegrationEventPublishing.publish_critical("message_sent",
      conversation_id: event.aggregate_id
    )
  end

  def handle(%DomainEvent{event_type: :messages_read} = event) do
    event
    |> promote()
    |> IntegrationEventPublishing.publish_best_effort("messages_read",
      conversation_id: event.aggregate_id
    )
  end

  def handle(%DomainEvent{event_type: :conversation_archived} = event) do
    event
    |> promote()
    |> IntegrationEventPublishing.publish_best_effort("conversation_archived",
      conversation_id: event.aggregate_id
    )
  end

  def handle(%DomainEvent{event_type: :conversations_archived} = event) do
    event
    |> promote()
    |> IntegrationEventPublishing.publish_best_effort("conversations_archived",
      aggregate_id: event.aggregate_id
    )
  end

  def handle(%DomainEvent{event_type: :participant_added} = event) do
    event
    |> promote()
    |> IntegrationEventPublishing.publish_critical("participant_added",
      conversation_id: event.aggregate_id
    )
  end

  def handle(%DomainEvent{event_type: :participant_removed} = event) do
    event
    |> promote()
    |> IntegrationEventPublishing.publish_critical("participant_removed",
      conversation_id: event.aggregate_id
    )
  end
end
