defmodule KlassHero.Participation.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents do
  @moduledoc """
  Maps Participation domain events to their integration events.

  `promote/1` is pure — `KlassHero.Shared.Outbox` calls it inside the producer's
  transaction so the integration event exists before anything commits. Returning
  `nil` for an unmapped event type reproduces today's semantics exactly: an event
  with no registration was never promoted either.

  `handle/1` is the bus-registered wrapper that promotes and publishes; it goes
  when this context's producers move to the outbox.

  ## Error strategy

  All events are **best-effort** on the bus path: the underlying state change is
  already durable, so the integration event is a notification, not a guarantee.
  The outbox replaces that with Oban retry.
  """

  alias KlassHero.Participation.Domain.Events.ParticipationIntegrationEvents
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.Domain.Events.IntegrationEvent
  alias KlassHero.Shared.IntegrationEventPublishing

  @spec promote(DomainEvent.t()) :: IntegrationEvent.t() | nil
  def promote(%DomainEvent{event_type: :session_created} = event) do
    ParticipationIntegrationEvents.session_created(event.aggregate_id, event.payload)
  end

  def promote(%DomainEvent{event_type: :session_started} = event) do
    ParticipationIntegrationEvents.session_started(event.aggregate_id, event.payload)
  end

  def promote(%DomainEvent{event_type: :session_completed} = event) do
    ParticipationIntegrationEvents.session_completed(event.aggregate_id, event.payload)
  end

  def promote(%DomainEvent{event_type: :session_cancelled} = event) do
    ParticipationIntegrationEvents.session_cancelled(event.aggregate_id, event.payload)
  end

  def promote(%DomainEvent{event_type: :sessions_generated} = event) do
    ParticipationIntegrationEvents.sessions_generated(event.aggregate_id, event.payload)
  end

  def promote(%DomainEvent{event_type: :roster_seeded} = event) do
    ParticipationIntegrationEvents.roster_seeded(event.aggregate_id, event.payload)
  end

  def promote(%DomainEvent{event_type: :child_checked_in} = event) do
    ParticipationIntegrationEvents.child_checked_in(event.aggregate_id, event.payload)
  end

  def promote(%DomainEvent{event_type: :child_checked_out} = event) do
    ParticipationIntegrationEvents.child_checked_out(event.aggregate_id, event.payload)
  end

  def promote(%DomainEvent{event_type: :child_marked_absent} = event) do
    ParticipationIntegrationEvents.child_marked_absent(event.aggregate_id, event.payload)
  end

  def promote(%DomainEvent{}), do: nil

  @doc """
  Handles a domain event by promoting it to the corresponding integration event.
  """
  @spec handle(DomainEvent.t()) :: :ok

  def handle(%DomainEvent{event_type: :session_created} = event) do
    event
    |> promote()
    |> IntegrationEventPublishing.publish_best_effort("session_created",
      session_id: event.aggregate_id
    )
  end

  def handle(%DomainEvent{event_type: :session_started} = event) do
    event
    |> promote()
    |> IntegrationEventPublishing.publish_best_effort("session_started",
      session_id: event.aggregate_id
    )
  end

  def handle(%DomainEvent{event_type: :session_completed} = event) do
    event
    |> promote()
    |> IntegrationEventPublishing.publish_best_effort("session_completed",
      session_id: event.aggregate_id
    )
  end

  def handle(%DomainEvent{event_type: :session_cancelled} = event) do
    event
    |> promote()
    |> IntegrationEventPublishing.publish_best_effort("session_cancelled",
      session_id: event.aggregate_id
    )
  end

  def handle(%DomainEvent{event_type: :sessions_generated} = event) do
    event
    |> promote()
    |> IntegrationEventPublishing.publish_best_effort("sessions_generated",
      program_id: event.aggregate_id
    )
  end

  def handle(%DomainEvent{event_type: :roster_seeded} = event) do
    event
    |> promote()
    |> IntegrationEventPublishing.publish_best_effort("roster_seeded",
      session_id: event.aggregate_id
    )
  end

  def handle(%DomainEvent{event_type: :child_checked_in} = event) do
    event
    |> promote()
    |> IntegrationEventPublishing.publish_best_effort("child_checked_in",
      record_id: event.aggregate_id
    )
  end

  def handle(%DomainEvent{event_type: :child_checked_out} = event) do
    event
    |> promote()
    |> IntegrationEventPublishing.publish_best_effort("child_checked_out",
      record_id: event.aggregate_id
    )
  end

  def handle(%DomainEvent{event_type: :child_marked_absent} = event) do
    event
    |> promote()
    |> IntegrationEventPublishing.publish_best_effort("child_marked_absent",
      record_id: event.aggregate_id
    )
  end
end
