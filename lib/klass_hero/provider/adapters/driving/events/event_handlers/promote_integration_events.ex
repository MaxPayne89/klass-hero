defmodule KlassHero.Provider.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents do
  @moduledoc """
  Promotes Provider domain events to integration events for cross-context communication.

  Registered on the Provider DomainEventBus.
  """

  alias KlassHero.Provider.Domain.Events.ProviderIntegrationEvents
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.IntegrationEventPublishing

  @spec handle(DomainEvent.t()) :: :ok | {:error, term()}
  # Messaging context needs to grant/revoke staff access to program broadcast conversations.
  def handle(%DomainEvent{event_type: :staff_assigned_to_program} = event) do
    # assigned_at is intentionally dropped: no cross-context consumer reads it, and
    # over durable Oban delivery a payload DateTime deserializes back to a string
    # (CriticalEventSerializer does not re-parse payload values). Keep the contract lean.
    payload = Map.take(event.payload, [:provider_id, :program_id, :staff_user_id])

    event.payload.staff_member_id
    |> ProviderIntegrationEvents.staff_assigned_to_program(payload)
    |> IntegrationEventPublishing.publish_critical("staff_assigned_to_program",
      staff_member_id: event.payload.staff_member_id
    )
  end

  def handle(%DomainEvent{event_type: :staff_unassigned_from_program} = event) do
    # unassigned_at dropped for the same reason as assigned_at above.
    payload = Map.take(event.payload, [:provider_id, :program_id, :staff_user_id])

    event.payload.staff_member_id
    |> ProviderIntegrationEvents.staff_unassigned_from_program(payload)
    |> IntegrationEventPublishing.publish_critical("staff_unassigned_from_program",
      staff_member_id: event.payload.staff_member_id
    )
  end
end
