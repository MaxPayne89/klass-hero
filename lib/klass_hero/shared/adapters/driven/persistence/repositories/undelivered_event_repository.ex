defmodule KlassHero.Shared.Adapters.Driven.Persistence.Repositories.UndeliveredEventRepository do
  @moduledoc """
  The dead-letter store for events delivery gave up on permanently.

  Written from `EventDeliveryWorker.compensate/2`, which the sweep over discarded
  jobs calls, and stamped or emptied by `EventDeliveryWorker.replay/1` and the
  delivery that follows it. Read by whoever is asking what was lost, and by the
  prune that forgets it later.

  ## `replayed_at` means "was ever replayed", not "is currently replaying"

  It is set when a replay is enqueued and never cleared — not by a replay that
  fails again, not by a second replay. That is what the prune keys on, and the
  reason is a composition one: a successful replay *deletes* its row, so if a
  re-failure cleared the stamp then every surviving row would read as unreplayed
  and the exemption below would spare all of them forever.
  """

  use KlassHero.Shared.Interaction

  import Ecto.Query

  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.Schemas.UndeliveredEvent

  @doc """
  Records the given rows, refreshing any event already recorded.

  `insert_all` rather than `Repo.insert`: this runs inside
  `JobCompensationRepository.compensate_once`'s transaction, and the
  `Ecto.ConstraintError` a duplicate would raise there aborts *that* transaction
  unless run at a savepoint (#1065) — taking the compensation marker with it.

  The conflict *replaces* rather than doing nothing, because a row can legitimately
  be written twice: the original failure, then a replay that failed again. Under
  `on_conflict: :nothing` the second write vanished and the row went on describing
  the first failure's consumers and timestamp.

  Three columns are deliberately left alone. `inserted_at` is the retention clock,
  which must not restart on every re-failure; `replayed_at` outlives any number of
  them by design; and `payload` is the same envelope for the same `event_id`.
  """
  @spec record_all([map()]) :: :ok
  def record_all([]), do: :ok

  def record_all(rows) when is_list(rows) do
    db_interaction operation: :record_all, entity: "undelivered_event" do
      Repo.insert_all(UndeliveredEvent, rows,
        conflict_target: :event_id,
        on_conflict: {:replace, [:topic, :missed_consumers, :job_id, :discarded_at]}
      )

      :ok
    end
  end

  @doc """
  Stamps the row as replayed, so the prune can tell it from one nobody noticed.
  """
  @spec mark_replayed(String.t()) :: :ok
  def mark_replayed(event_id) when is_binary(event_id) do
    db_interaction operation: :mark_replayed, entity: "undelivered_event" do
      UndeliveredEvent
      |> where(event_id: ^event_id)
      |> Repo.update_all(set: [replayed_at: DateTime.utc_now()])

      :ok
    end
  end

  @doc """
  Forgets the event, every missed consumer having finally landed.

  Deleting rather than marking: the row's whole meaning is outstanding work, so one
  that has none left says nothing true. A row already gone is not an error — the
  delete is the last step of a replay, and re-running a replay whose consumers all
  succeeded reaches here a second time.
  """
  @spec resolve(String.t()) :: :ok
  def resolve(event_id) when is_binary(event_id) do
    db_interaction operation: :resolve, entity: "undelivered_event" do
      UndeliveredEvent
      |> where(event_id: ^event_id)
      |> Repo.delete_all()

      :ok
    end
  end

  @doc """
  Deletes expired records, returning how many went.

  The envelope carries whatever personal data its event carried, so its retention
  is a rule someone chose rather than however long nobody deleted it.

  A row nobody has replayed is held past `cutoff`: it is the only trace of a
  reaction that never ran, and pruning it destroys the payload the recovery needs
  before anyone has looked. `backstop` is what keeps that from becoming an
  open-ended hold — it applies to every row, replayed or not.
  """
  @spec prune(DateTime.t(), DateTime.t()) :: non_neg_integer()
  def prune(%DateTime{} = cutoff, %DateTime{} = backstop) do
    db_interaction operation: :prune, entity: "undelivered_event" do
      {deleted, _returning} =
        Repo.delete_all(
          from(u in UndeliveredEvent,
            where: (u.inserted_at < ^cutoff and not is_nil(u.replayed_at)) or u.inserted_at < ^backstop
          )
        )

      deleted
    end
  end

  @doc """
  How many unreplayed records the exemption spared this pass.

  Reported rather than silent: a row held here is one a person still has to act on,
  and a growing count is the backlog nobody has looked at yet.
  """
  @spec count_held(DateTime.t(), DateTime.t()) :: non_neg_integer()
  def count_held(%DateTime{} = cutoff, %DateTime{} = backstop) do
    db_interaction operation: :count_held, entity: "undelivered_event" do
      Repo.aggregate(
        from(u in UndeliveredEvent,
          where: u.inserted_at < ^cutoff and is_nil(u.replayed_at) and u.inserted_at >= ^backstop
        ),
        :count
      )
    end
  end
end
