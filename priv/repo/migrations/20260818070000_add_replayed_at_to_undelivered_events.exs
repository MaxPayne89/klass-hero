defmodule KlassHero.Repo.Migrations.AddReplayedAtToUndeliveredEvents do
  use Ecto.Migration

  # Nullable with no backfill: an existing row has never been replayed, which is
  # exactly what NULL says. No index either — the prune's other predicate is
  # `inserted_at`, already indexed, and this table is empty in the healthy case.
  def change do
    alter table(:undelivered_events) do
      add :replayed_at, :utc_datetime_usec
    end
  end
end
