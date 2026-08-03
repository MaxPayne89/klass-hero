defmodule KlassHero.Repo.Migrations.CreateUndeliveredEvents do
  @moduledoc """
  Dead-letter record for an integration event whose delivery gave up permanently.

  `payload` holds the whole serialized `Event` envelope rather than just its
  `payload` field, because replaying one means handing those exact args back to
  `EventDeliveryWorker` — `%{"events" => [payload]}`. Consumers that already
  succeeded are skipped on replay by `processed_events`, which is never pruned.

  No foreign key to `oban_jobs`, for the same reason `job_compensations` has none:
  `Oban.Plugins.Pruner` deletes those rows after 7 days, and this record outliving
  the job it describes is the entire point.

  `event_id` is unique because that uniqueness *is* the idempotency guarantee —
  the sweep may reach the same dead job more than once, and the database refuses
  the duplicate rather than careful code.

  Rows are pruned after 90 days by `CompensationSweepWorker`: the envelope carries
  personal data (the last real production loss carried a parent's email), so its
  retention is an explicit rule rather than an accident of what nobody deleted.
  """

  use Ecto.Migration

  def change do
    create table(:undelivered_events, primary_key: false) do
      add :event_id, :uuid, null: false
      add :topic, :string, null: false
      add :payload, :map, null: false
      add :missed_consumers, {:array, :string}, null: false
      add :job_id, :bigint, null: false
      add :discarded_at, :utc_datetime_usec
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:undelivered_events, [:event_id])

    # The prune's access path. Every other read of this table is a human looking
    # at a handful of rows, so this is the only index worth its write cost.
    create index(:undelivered_events, [:inserted_at])
  end
end
