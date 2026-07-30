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

  ## Only what someone consumes is staged

  An event with no registered consumer is dropped rather than staged: it would
  give the delivery job nothing to do. The routing table is the one place that
  decides, so there is no second list to keep in agreement with it.

  ## Failure

  `stage/2` raises rather than returning an error. Inside a transaction that is
  the only safe behaviour — a returned error is ignorable, and ignoring it would
  commit a state change whose events were dropped.
  """

  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Events.EventConsumerRegistry
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  @doc """
  Stages one or more events for durable delivery, in the order given.

  `context` is the producing context module (`KlassHero.Participation`). It is
  accepted for symmetry with `transact/2` and for call-site readability; the
  event carries its own source context.
  """
  @spec stage(module(), IntegrationEvent.t() | [IntegrationEvent.t()]) :: :ok
  def stage(context, events) when is_atom(context) do
    events
    |> List.wrap()
    |> Enum.filter(&consumed?/1)
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
  same-context handlers on the `DomainEventBus` — the seven that do business
  work — which stay synchronous and post-commit.

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
  @spec transact(module(), (-> {:ok, result, [IntegrationEvent.t()]} | {:error, term()})) ::
          {:ok, {result, [IntegrationEvent.t()]}} | {:error, term()}
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

  # Per event, not per batch: one unrouted event must not strand the siblings
  # staged in the same transaction.
  defp consumed?(%IntegrationEvent{} = event) do
    event |> IntegrationEvent.topic() |> EventConsumerRegistry.consumers_for() != []
  end

  defp adapter, do: Application.fetch_env!(:klass_hero, :outbox)[:module]
end
