defmodule KlassHero.Enrollment.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents do
  @moduledoc """
  Promotes Enrollment domain events to integration events for cross-context communication.

  Registered on the Enrollment DomainEventBus at priority 10.
  """

  alias KlassHero.Enrollment.Domain.Events.EnrollmentIntegrationEvents
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.IntegrationEventPublishing

  @spec handle(DomainEvent.t()) :: :ok | {:error, term()}
  def handle(%DomainEvent{event_type: :participant_policy_set} = event) do
    event.aggregate_id
    |> EnrollmentIntegrationEvents.participant_policy_set(event.payload)
    |> IntegrationEventPublishing.publish_critical("participant_policy_set",
      program_id: event.aggregate_id
    )
  end

  def handle(%DomainEvent{event_type: :invite_claimed} = event) do
    event.payload.invite_id
    |> EnrollmentIntegrationEvents.invite_claimed(event.payload)
    |> IntegrationEventPublishing.publish_critical("invite_claimed",
      invite_id: event.payload.invite_id
    )
  end

  def handle(%DomainEvent{event_type: :enrollment_cancelled} = event) do
    event.payload.enrollment_id
    |> EnrollmentIntegrationEvents.enrollment_cancelled(event.payload)
    |> IntegrationEventPublishing.publish_critical("enrollment_cancelled",
      enrollment_id: event.payload.enrollment_id
    )
  end

  def handle(%DomainEvent{event_type: :enrollment_created} = event) do
    event.payload.enrollment_id
    |> EnrollmentIntegrationEvents.enrollment_created(event.payload)
    |> IntegrationEventPublishing.publish_critical("enrollment_created",
      enrollment_id: event.payload.enrollment_id
    )
  end
end
