defmodule KlassHero.Repo.Migrations.CreateJobCompensations do
  @moduledoc """
  Ledger recording that a permanently-dead Oban job has had its compensating
  business fact established.

  Deliberately carries no foreign key to `oban_jobs`: `Oban.Plugins.Pruner`
  deletes those rows on its own schedule (7 days here), and a compensation
  outliving the job row it describes is correct, not orphaned.

  `job_id` is unique because that uniqueness *is* the exactly-once guarantee —
  the sweep inserts the marker and runs the compensation in one transaction, so
  a duplicate is refused by the database rather than by careful code.
  """

  use Ecto.Migration

  def change do
    create table(:job_compensations, primary_key: false) do
      add :job_id, :bigint, null: false
      add :worker, :string, null: false
      add :compensated_at, :utc_datetime_usec, null: false
    end

    create unique_index(:job_compensations, [:job_id])
  end
end
