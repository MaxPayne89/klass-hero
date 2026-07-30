defmodule KlassHero.Enrollment.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents do
  @moduledoc """
  Maps Enrollment domain events to their integration events.

  `promote/1` is pure — `KlassHero.Shared.Outbox` calls it inside the producer's
  transaction so the integration event exists before anything commits. Returning
  `nil` for an unmapped event type reproduces today's semantics exactly: an event
  with no registration was never promoted either.

  Only `:participant_policy_set` keys off `aggregate_id`; the other three take
  their entity id out of the payload.

  `handle/1` is the bus-registered wrapper that promotes and publishes; it goes
  when this context's producers move to the outbox.
  """

  alias KlassHero.Enrollment.Domain.Events.EnrollmentIntegrationEvents
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.Domain.Events.IntegrationEvent
  alias KlassHero.Shared.IntegrationEventPublishing

  @spec promote(DomainEvent.t()) :: IntegrationEvent.t() | nil
  def promote(%DomainEvent{event_type: :participant_policy_set} = event) do
    EnrollmentIntegrationEvents.participant_policy_set(event.aggregate_id, event.payload)
  end

  def promote(%DomainEvent{event_type: :invite_claimed} = event) do
    EnrollmentIntegrationEvents.invite_claimed(event.payload.invite_id, event.payload)
  end

  def promote(%DomainEvent{event_type: :enrollment_cancelled} = event) do
    EnrollmentIntegrationEvents.enrollment_cancelled(event.payload.enrollment_id, event.payload)
  end

  def promote(%DomainEvent{event_type: :enrollment_created} = event) do
    EnrollmentIntegrationEvents.enrollment_created(event.payload.enrollment_id, event.payload)
  end

  def promote(%DomainEvent{}), do: nil

  @spec handle(DomainEvent.t()) :: :ok | {:error, term()}
  def handle(%DomainEvent{event_type: :participant_policy_set} = event) do
    event
    |> promote()
    |> IntegrationEventPublishing.publish_critical("participant_policy_set",
      program_id: event.aggregate_id
    )
  end

  def handle(%DomainEvent{event_type: :invite_claimed} = event) do
    event
    |> promote()
    |> IntegrationEventPublishing.publish_critical("invite_claimed",
      invite_id: event.payload.invite_id
    )
  end

  def handle(%DomainEvent{event_type: :enrollment_cancelled} = event) do
    event
    |> promote()
    |> IntegrationEventPublishing.publish_critical("enrollment_cancelled",
      enrollment_id: event.payload.enrollment_id
    )
  end

  def handle(%DomainEvent{event_type: :enrollment_created} = event) do
    event
    |> promote()
    |> IntegrationEventPublishing.publish_critical("enrollment_created",
      enrollment_id: event.payload.enrollment_id
    )
  end
end
