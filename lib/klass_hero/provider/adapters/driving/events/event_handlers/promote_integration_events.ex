defmodule KlassHero.Provider.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents do
  @moduledoc """
  Maps Provider domain events to their integration events.

  `promote/1` is pure — `KlassHero.Shared.Outbox` calls it inside the producer's
  transaction so the integration event exists before anything commits. Returning
  `nil` for an unmapped event type reproduces today's semantics exactly: an event
  with no registration was never promoted either.

  `handle/1` is the bus-registered wrapper that promotes and publishes; it goes
  when this context's producers move to the outbox.
  """

  alias KlassHero.Provider.Domain.Events.ProviderIntegrationEvents
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.Domain.Events.IntegrationEvent
  alias KlassHero.Shared.IntegrationEventPublishing

  # assigned_at/unassigned_at are intentionally dropped: no cross-context consumer reads them,
  # and over durable Oban delivery a payload DateTime deserializes back to a string
  # (CriticalEventSerializer does not re-parse payload values). Keep the contract lean.
  @carried_keys [:provider_id, :program_id, :staff_user_id]

  @spec promote(DomainEvent.t()) :: IntegrationEvent.t() | nil
  # Messaging context needs to grant/revoke staff access to program broadcast conversations.
  def promote(%DomainEvent{event_type: :staff_assigned_to_program} = event) do
    ProviderIntegrationEvents.staff_assigned_to_program(
      event.payload.staff_member_id,
      Map.take(event.payload, @carried_keys)
    )
  end

  def promote(%DomainEvent{event_type: :staff_unassigned_from_program} = event) do
    ProviderIntegrationEvents.staff_unassigned_from_program(
      event.payload.staff_member_id,
      Map.take(event.payload, @carried_keys)
    )
  end

  def promote(%DomainEvent{}), do: nil

  @spec handle(DomainEvent.t()) :: :ok | {:error, term()}
  def handle(%DomainEvent{event_type: :staff_assigned_to_program} = event) do
    event
    |> promote()
    |> IntegrationEventPublishing.publish_critical("staff_assigned_to_program",
      staff_member_id: event.payload.staff_member_id
    )
  end

  def handle(%DomainEvent{event_type: :staff_unassigned_from_program} = event) do
    event
    |> promote()
    |> IntegrationEventPublishing.publish_critical("staff_unassigned_from_program",
      staff_member_id: event.payload.staff_member_id
    )
  end
end
