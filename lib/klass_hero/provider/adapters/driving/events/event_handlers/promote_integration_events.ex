defmodule KlassHero.Provider.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents do
  @moduledoc """
  Promotes Provider domain events to integration events for cross-context communication.

  Registered on the Provider DomainEventBus.
  """

  alias KlassHero.Provider.Domain.Events.ProviderIntegrationEvents
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.IntegrationEventPublishing

  @spec handle(DomainEvent.t()) :: :ok | {:error, term()}
  def handle(%DomainEvent{event_type: :staff_assigned_to_program} = event) do
    # Trigger: staff_assigned_to_program domain event dispatched from AssignStaffToProgram use case
    # Why: Messaging context needs to grant the staff member access to program broadcast conversations
    # Outcome: publish integration event on topic integration:provider:staff_assigned_to_program
    event.payload.staff_member_id
    |> ProviderIntegrationEvents.staff_assigned_to_program(event.payload)
    |> IntegrationEventPublishing.publish_critical("staff_assigned_to_program",
      staff_member_id: event.payload.staff_member_id
    )
  end

  def handle(%DomainEvent{event_type: :staff_unassigned_from_program} = event) do
    # Trigger: staff_unassigned_from_program domain event dispatched from UnassignStaffFromProgram use case
    # Why: Messaging context needs to revoke the staff member's access to program broadcast conversations
    # Outcome: publish integration event on topic integration:provider:staff_unassigned_from_program
    event.payload.staff_member_id
    |> ProviderIntegrationEvents.staff_unassigned_from_program(event.payload)
    |> IntegrationEventPublishing.publish_critical("staff_unassigned_from_program",
      staff_member_id: event.payload.staff_member_id
    )
  end

  def handle(%DomainEvent{event_type: :incident_reported} = event) do
    # Trigger: incident_reported domain event dispatched from SubmitIncidentReport use case
    # Why: safety-domain events need durable delivery to future consumers (admin, notifications)
    # Outcome: publish integration event on topic integration:provider:incident_reported
    event.aggregate_id
    |> ProviderIntegrationEvents.incident_reported(event.payload)
    |> IntegrationEventPublishing.publish_critical("incident_reported",
      incident_report_id: event.aggregate_id
    )
  end
end
