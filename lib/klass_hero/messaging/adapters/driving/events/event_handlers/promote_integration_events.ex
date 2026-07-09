defmodule KlassHero.Messaging.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents do
  @moduledoc """
  Promotes Messaging domain events to integration events for cross-context communication.

  Registered on the Messaging DomainEventBus. When a relevant domain event is
  dispatched, this handler creates the corresponding integration event and
  publishes it via PubSub.

  ## Error strategy

  - **Critical events** (`:conversation_created`, `:message_sent`): Propagate
    publish failures as `{:error, reason}` so the DomainEventBus can report
    the failure to the calling use case.
  - **Best-effort events** (`:user_data_anonymized`, `:messages_read`,
    `:conversation_archived`, `:conversations_archived`): Swallow publish
    failures and return `:ok`. The underlying state change is already durable;
    the integration event is a notification, not a guarantee.
  """

  alias KlassHero.Messaging.Domain.Events.MessagingIntegrationEvents
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.IntegrationEventPublishing

  @doc """
  Handles a domain event by promoting it to the corresponding integration event.
  """
  @spec handle(DomainEvent.t()) :: :ok | {:error, term()}
  def handle(%DomainEvent{event_type: :user_data_anonymized} = event) do
    user_id = event.payload.user_id

    MessagingIntegrationEvents.message_data_anonymized(user_id)
    |> IntegrationEventPublishing.publish_best_effort("message_data_anonymized",
      user_id: user_id
    )
  end

  def handle(%DomainEvent{event_type: :conversation_created} = event) do
    event.aggregate_id
    |> MessagingIntegrationEvents.conversation_created(event.payload)
    |> IntegrationEventPublishing.publish_critical("conversation_created",
      conversation_id: event.aggregate_id
    )
  end

  def handle(%DomainEvent{event_type: :message_sent} = event) do
    event.aggregate_id
    |> MessagingIntegrationEvents.message_sent(event.payload)
    |> IntegrationEventPublishing.publish_critical("message_sent",
      conversation_id: event.aggregate_id
    )
  end

  def handle(%DomainEvent{event_type: :messages_read} = event) do
    MessagingIntegrationEvents.messages_read(event.aggregate_id, event.payload)
    |> IntegrationEventPublishing.publish_best_effort("messages_read",
      conversation_id: event.aggregate_id
    )
  end

  def handle(%DomainEvent{event_type: :conversation_archived} = event) do
    MessagingIntegrationEvents.conversation_archived(event.aggregate_id, event.payload)
    |> IntegrationEventPublishing.publish_best_effort("conversation_archived",
      conversation_id: event.aggregate_id
    )
  end

  def handle(%DomainEvent{event_type: :conversations_archived} = event) do
    MessagingIntegrationEvents.conversations_archived(event.aggregate_id, event.payload)
    |> IntegrationEventPublishing.publish_best_effort("conversations_archived",
      aggregate_id: event.aggregate_id
    )
  end

  def handle(%DomainEvent{event_type: :participant_added} = event) do
    event.aggregate_id
    |> MessagingIntegrationEvents.participant_added(event.payload)
    |> IntegrationEventPublishing.publish_critical("participant_added",
      conversation_id: event.aggregate_id
    )
  end

  def handle(%DomainEvent{event_type: :participant_removed} = event) do
    event.aggregate_id
    |> MessagingIntegrationEvents.participant_removed(event.payload)
    |> IntegrationEventPublishing.publish_critical("participant_removed",
      conversation_id: event.aggregate_id
    )
  end
end
