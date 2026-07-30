defmodule KlassHero.StubPromoter do
  @moduledoc """
  A promoter for `Shared.Outbox`'s own tests.

  The outbox's contract is "consult the configured promoter for this context",
  not "Family promotes children" — so its tests should not break each time a
  real context stops promoting. Registered via `:event_promoters` in the test
  that needs it. Goes when promotion does.
  """

  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  @spec promote(DomainEvent.t()) :: IntegrationEvent.t() | nil
  def promote(%DomainEvent{event_type: :program_created} = event) do
    IntegrationEvent.new(:program_created, :program_catalog, :program, event.aggregate_id, event.payload)
  end

  def promote(%DomainEvent{}), do: nil
end
