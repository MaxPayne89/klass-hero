defmodule KlassHero.ProgramCatalog.Adapters.Driving.Events.EventHandlers.PromoteIntegrationEvents do
  @moduledoc """
  Maps ProgramCatalog domain events to their integration events.

  `promote/1` is pure — `KlassHero.Shared.Outbox` calls it inside the producer's
  transaction so the integration event exists before anything commits. Returning
  `nil` for an unmapped event type reproduces today's semantics exactly: an event
  with no registration was never promoted either.

  `handle/1` is the bus-registered wrapper that promotes and publishes; it goes
  when this context's producers move to the outbox.
  """

  alias KlassHero.ProgramCatalog.Domain.Events.ProgramCatalogIntegrationEvents
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.Domain.Events.IntegrationEvent
  alias KlassHero.Shared.IntegrationEventPublishing

  @spec promote(DomainEvent.t()) :: IntegrationEvent.t() | nil
  def promote(%DomainEvent{event_type: :program_created} = event) do
    ProgramCatalogIntegrationEvents.program_created(event.aggregate_id, event.payload)
  end

  def promote(%DomainEvent{event_type: :program_updated} = event) do
    ProgramCatalogIntegrationEvents.program_updated(event.aggregate_id, event.payload)
  end

  def promote(%DomainEvent{}), do: nil

  @spec handle(DomainEvent.t()) :: :ok | {:error, term()}
  def handle(%DomainEvent{event_type: :program_created} = event) do
    event
    |> promote()
    |> IntegrationEventPublishing.publish_critical("program_created",
      program_id: event.aggregate_id
    )
  end

  def handle(%DomainEvent{event_type: :program_updated} = event) do
    event
    |> promote()
    |> IntegrationEventPublishing.publish_critical("program_updated",
      program_id: event.aggregate_id
    )
  end
end
