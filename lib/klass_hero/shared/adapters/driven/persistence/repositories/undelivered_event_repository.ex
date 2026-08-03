defmodule KlassHero.Shared.Adapters.Driven.Persistence.Repositories.UndeliveredEventRepository do
  @moduledoc """
  The dead-letter store for events delivery gave up on permanently.

  Written only from `EventDeliveryWorker.compensate/2`, which the sweep over
  discarded jobs calls. Read by whoever is asking what was lost, and by the prune
  that forgets it 90 days later.
  """

  use KlassHero.Shared.Interaction

  import Ecto.Query

  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.Schemas.UndeliveredEvent

  @doc """
  Records the given rows, ignoring any event already recorded.

  `insert_all` with `on_conflict: :nothing` rather than `Repo.insert`: this runs
  inside `JobCompensationRepository.compensate_once`'s transaction, and the
  `Ecto.ConstraintError` a duplicate would raise there aborts *that* transaction
  unless run at a savepoint (#1065) — taking the compensation marker with it.
  """
  @spec record_all([map()]) :: :ok
  def record_all([]), do: :ok

  def record_all(rows) when is_list(rows) do
    db_interaction operation: :record_all, entity: "undelivered_event" do
      Repo.insert_all(UndeliveredEvent, rows, on_conflict: :nothing)
      :ok
    end
  end

  @doc """
  Deletes records staged before `cutoff`, returning how many went.

  The envelope carries whatever personal data its event carried, so its retention
  is a rule someone chose rather than however long nobody deleted it.
  """
  @spec prune(DateTime.t()) :: non_neg_integer()
  def prune(%DateTime{} = cutoff) do
    db_interaction operation: :prune, entity: "undelivered_event" do
      {deleted, _returning} =
        Repo.delete_all(from(u in UndeliveredEvent, where: u.inserted_at < ^cutoff))

      deleted
    end
  end
end
