defmodule KlassHero.Participation.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents do
  @moduledoc """
  Promotes Participation domain events to integration events for cross-context communication.

  Registered on the Participation DomainEventBus. When a relevant domain event is
  dispatched, this handler creates the corresponding integration event and
  publishes it via PubSub.

  ## Error strategy

  All events are **best-effort**: the underlying state change is already durable,
  so the integration event is a notification, not a guarantee. Publish failures
  are swallowed and return `:ok`.
  """

  alias KlassHero.Participation.Domain.Events.ParticipationIntegrationEvents
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.IntegrationEventPublishing

  @doc """
  Handles a domain event by promoting it to the corresponding integration event.
  """
  @spec handle(DomainEvent.t()) :: :ok

  def handle(%DomainEvent{event_type: :session_created} = event) do
    ParticipationIntegrationEvents.session_created(event.aggregate_id, event.payload)
    |> IntegrationEventPublishing.publish_best_effort("session_created",
      session_id: event.aggregate_id
    )
  end

  def handle(%DomainEvent{event_type: :session_started} = event) do
    ParticipationIntegrationEvents.session_started(event.aggregate_id, event.payload)
    |> IntegrationEventPublishing.publish_best_effort("session_started",
      session_id: event.aggregate_id
    )
  end

  def handle(%DomainEvent{event_type: :session_completed} = event) do
    ParticipationIntegrationEvents.session_completed(event.aggregate_id, event.payload)
    |> IntegrationEventPublishing.publish_best_effort("session_completed",
      session_id: event.aggregate_id
    )
  end

  def handle(%DomainEvent{event_type: :session_cancelled} = event) do
    ParticipationIntegrationEvents.session_cancelled(event.aggregate_id, event.payload)
    |> IntegrationEventPublishing.publish_best_effort("session_cancelled",
      session_id: event.aggregate_id
    )
  end

  def handle(%DomainEvent{event_type: :roster_seeded} = event) do
    ParticipationIntegrationEvents.roster_seeded(event.aggregate_id, event.payload)
    |> IntegrationEventPublishing.publish_best_effort("roster_seeded",
      session_id: event.aggregate_id
    )
  end

  def handle(%DomainEvent{event_type: :child_checked_in} = event) do
    ParticipationIntegrationEvents.child_checked_in(event.aggregate_id, event.payload)
    |> IntegrationEventPublishing.publish_best_effort("child_checked_in",
      record_id: event.aggregate_id
    )
  end

  def handle(%DomainEvent{event_type: :child_checked_out} = event) do
    ParticipationIntegrationEvents.child_checked_out(event.aggregate_id, event.payload)
    |> IntegrationEventPublishing.publish_best_effort("child_checked_out",
      record_id: event.aggregate_id
    )
  end

  def handle(%DomainEvent{event_type: :child_marked_absent} = event) do
    ParticipationIntegrationEvents.child_marked_absent(event.aggregate_id, event.payload)
    |> IntegrationEventPublishing.publish_best_effort("child_marked_absent",
      record_id: event.aggregate_id
    )
  end

  def handle(%DomainEvent{event_type: :behavioral_note_submitted} = event) do
    ParticipationIntegrationEvents.behavioral_note_submitted(event.aggregate_id, event.payload)
    |> IntegrationEventPublishing.publish_best_effort("behavioral_note_submitted",
      note_id: event.aggregate_id
    )
  end

  def handle(%DomainEvent{event_type: :behavioral_note_approved} = event) do
    ParticipationIntegrationEvents.behavioral_note_approved(event.aggregate_id, event.payload)
    |> IntegrationEventPublishing.publish_best_effort("behavioral_note_approved",
      note_id: event.aggregate_id
    )
  end

  def handle(%DomainEvent{event_type: :behavioral_note_rejected} = event) do
    ParticipationIntegrationEvents.behavioral_note_rejected(event.aggregate_id, event.payload)
    |> IntegrationEventPublishing.publish_best_effort("behavioral_note_rejected",
      note_id: event.aggregate_id
    )
  end
end
