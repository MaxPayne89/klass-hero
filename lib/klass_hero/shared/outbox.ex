defmodule KlassHero.Shared.Outbox do
  @moduledoc """
  Hands a transaction's events to durable delivery, from inside that transaction.

  Producers call `stage/2` *within* the `Repo.transaction` that changed the state,
  so the event and the fact it describes commit or roll back together. There is no
  commit-then-publish window to crash in, because there is one commit.

      Repo.transaction(fn ->
        {:ok, session} = insert_session(attrs)
        Outbox.stage(@context, ParticipationEvents.session_created(session))
        session
      end)

  ## Promotion happens here, in the transaction

  Producers hand over the events they already build — domain events — and this
  module maps them to integration events before staging, using the context's
  promoter from `:event_promoters`. Promotion is pure, so doing it early costs
  nothing and means the outbox only ever carries one kind of event.

  A domain event whose context has no promoter, or whose type the promoter does
  not map, stages nothing. That is exactly today's behaviour: an event with no
  bus registration was never promoted either.

  One consequence worth naming: `IntegrationEvent.new/6` validates the payload
  (#1010), so a malformed payload now aborts the producer's transaction instead of
  quietly losing the event after the write succeeded. That is the trade this seam
  is for.

  ## Failure

  `stage/2` raises rather than returning an error. Inside a transaction that is
  the only safe behaviour — a returned error is ignorable, and ignoring it would
  commit a state change whose events were dropped.
  """

  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  @type stageable :: DomainEvent.t() | IntegrationEvent.t()

  @doc """
  Stages one or more events for durable delivery, in the order given.

  `context` is the producing context module (`KlassHero.Participation`), used to
  find the promoter for domain events. Integration events pass straight through.
  """
  @spec stage(module(), stageable() | [stageable()]) :: :ok
  def stage(context, events) when is_atom(context) do
    events
    |> List.wrap()
    |> Enum.flat_map(&to_integration_events(context, &1))
    |> stage_all()
  end

  defp stage_all([]), do: :ok
  defp stage_all(events), do: adapter().stage(events)

  defp to_integration_events(_context, %IntegrationEvent{} = event), do: [event]

  defp to_integration_events(context, %DomainEvent{} = event) do
    case promoter(context) do
      nil -> []
      module -> List.wrap(module.promote(event))
    end
  end

  defp promoter(context) do
    :klass_hero
    |> Application.get_env(:event_promoters, %{})
    |> Map.get(context)
  end

  defp adapter, do: Application.fetch_env!(:klass_hero, :outbox)[:module]
end
