defmodule KlassHero.ProgramCatalog.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents do
  @moduledoc """
  Promotes ProgramCatalog domain events to integration events for cross-context communication.

  Registered on the ProgramCatalog DomainEventBus at priority 10.
  """

  alias KlassHero.ProgramCatalog.Domain.Events.ProgramCatalogIntegrationEvents
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.IntegrationEventPublishing

  @spec handle(DomainEvent.t()) :: :ok | {:error, term()}
  def handle(%DomainEvent{event_type: :program_created} = event) do
    event.aggregate_id
    |> ProgramCatalogIntegrationEvents.program_created(event.payload)
    |> IntegrationEventPublishing.publish_critical("program_created",
      program_id: event.aggregate_id
    )
  end

  def handle(%DomainEvent{event_type: :program_updated} = event) do
    event.aggregate_id
    |> ProgramCatalogIntegrationEvents.program_updated(event.payload)
    |> IntegrationEventPublishing.publish_critical("program_updated",
      program_id: event.aggregate_id
    )
  end
end
