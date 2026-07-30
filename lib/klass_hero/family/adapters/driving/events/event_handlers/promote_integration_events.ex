defmodule KlassHero.Family.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents do
  @moduledoc """
  Maps Family domain events to their integration events.

  `promote/1` is pure — `KlassHero.Shared.Outbox` calls it inside the producer's
  transaction so the integration event exists before anything commits. Returning
  `nil` for an unmapped event type reproduces today's semantics exactly: an event
  with no registration was never promoted either.

  These four all key off `payload`, not `aggregate_id`.

  `handle/1` is the bus-registered wrapper that promotes and publishes; it goes
  when this context's producers move to the outbox.

  ## Error strategy

  The bus path propagates publish failures — the GDPR anonymization cascade
  requires confirmation that downstream contexts were notified, and a failure
  halts the `reduce_while` loop in the Family facade. The outbox replaces that
  with Oban retry.
  """

  alias KlassHero.Family.Domain.Events.FamilyIntegrationEvents
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.Domain.Events.IntegrationEvent
  alias KlassHero.Shared.IntegrationEventPublishing

  @spec promote(DomainEvent.t()) :: IntegrationEvent.t() | nil
  def promote(%DomainEvent{event_type: :child_data_anonymized} = event) do
    FamilyIntegrationEvents.child_data_anonymized(event.payload.child_id)
  end

  def promote(%DomainEvent{event_type: :invite_family_ready} = event) do
    FamilyIntegrationEvents.invite_family_ready(event.payload.invite_id, event.payload)
  end

  def promote(%DomainEvent{event_type: :child_created} = event) do
    FamilyIntegrationEvents.child_created(event.payload.child_id, event.payload)
  end

  def promote(%DomainEvent{event_type: :child_updated} = event) do
    FamilyIntegrationEvents.child_updated(event.payload.child_id, event.payload)
  end

  def promote(%DomainEvent{}), do: nil

  @doc """
  Handles a domain event by promoting it to the corresponding integration event.
  """
  @spec handle(DomainEvent.t()) :: :ok | {:error, term()}
  def handle(%DomainEvent{} = event) do
    case promote(event) do
      %IntegrationEvent{} = integration_event -> IntegrationEventPublishing.publish(integration_event)
      nil -> :ok
    end
  end
end
