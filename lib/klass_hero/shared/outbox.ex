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

  alias KlassHero.Repo
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

  @doc """
  Runs `fun` in a transaction and stages the events it produced inside that same
  transaction.

  The shape every migrated producer uses. `fun` does the writes and returns the
  entity together with the events describing them; those events are staged before
  the commit, so there is no moment where the write is durable and the events are
  not.

  The events come back out with the result because some of them still have
  same-context handlers on the `DomainEventBus` — `NotifyLiveViews` and the seven
  that do business work — which stay synchronous and post-commit.

      def create_session(params) do
        with {:ok, session} <- ProgramSession.new(attrs),
             {:ok, {persisted, events}} <-
               Outbox.transact(@context, fn ->
                 with {:ok, persisted} <- insert_session(session) do
                   {:ok, persisted, [ParticipationEvents.session_created(persisted)]}
                 end
               end) do
          Enum.each(events, &DomainEventBus.dispatch(@context, &1))
          {:ok, persisted}
        end
      end
  """
  @spec transact(module(), (-> {:ok, result, [stageable()]} | {:error, term()})) ::
          {:ok, {result, [stageable()]}} | {:error, term()}
        when result: term()
  def transact(context, fun) when is_atom(context) and is_function(fun, 0) do
    # An `Ecto.Multi` rather than `Repo.transaction(fn -> ... Repo.rollback(reason) end)`
    # because producers run inside outer transactions: a critical event handler executes
    # within `ProcessedEventRepository.execute_atomically`'s Multi, and a nested
    # `Repo.rollback` aborts *that* Multi with "rolling back unexpectedly" instead of
    # just this write. A failing `Multi.run` step expresses the same intent with no
    # rollback call to escape.
    Ecto.Multi.new()
    |> Ecto.Multi.run(:work, fn _repo, _changes ->
      # Deliberately no catch-all: a producer returning a bare {:ok, entity} is a
      # half-migrated call site, and raising on its first run beats staging nothing.
      case fun.() do
        {:ok, result, events} -> {:ok, {result, events}}
        {:error, reason} -> {:error, reason}
      end
    end)
    |> Ecto.Multi.run(:stage, fn _repo, %{work: {_result, events}} ->
      stage(context, events)
      {:ok, :staged}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{work: work}} -> {:ok, work}
      # The caller's own reason, so `with {:ok, _} <- ...` chains keep matching the
      # same error shapes they matched before the outbox.
      {:error, :work, reason, _changes} -> {:error, reason}
    end
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
