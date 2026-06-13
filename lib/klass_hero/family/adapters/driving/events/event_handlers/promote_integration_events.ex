defmodule KlassHero.Family.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents do
  @moduledoc """
  Promotes Family domain events to integration events for cross-context communication.

  Registered on the Family DomainEventBus. When a relevant domain event is
  dispatched, this handler creates the corresponding integration event and
  publishes it via PubSub.

  ## Error strategy

  Propagates publish failures — the GDPR anonymization cascade requires
  confirmation that downstream contexts were notified. A publish failure
  halts the reduce_while loop in the Family facade.
  """

  alias KlassHero.Family.Domain.Events.FamilyIntegrationEvents
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.IntegrationEventPublishing

  @doc """
  Handles a domain event by promoting it to the corresponding integration event.
  """
  @spec handle(DomainEvent.t()) :: :ok | {:error, term()}
  def handle(%DomainEvent{event_type: :child_data_anonymized} = event) do
    child_id = event.payload.child_id

    child_id
    |> FamilyIntegrationEvents.child_data_anonymized()
    |> IntegrationEventPublishing.publish()
  end

  def handle(%DomainEvent{event_type: :invite_family_ready} = event) do
    event.payload.invite_id
    |> FamilyIntegrationEvents.invite_family_ready(event.payload)
    |> IntegrationEventPublishing.publish()
  end

  def handle(%DomainEvent{event_type: :child_created} = event) do
    event.payload.child_id
    |> FamilyIntegrationEvents.child_created(event.payload)
    |> IntegrationEventPublishing.publish()
  end

  def handle(%DomainEvent{event_type: :child_updated} = event) do
    event.payload.child_id
    |> FamilyIntegrationEvents.child_updated(event.payload)
    |> IntegrationEventPublishing.publish()
  end
end
