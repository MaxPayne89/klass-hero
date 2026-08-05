defmodule KlassHero.Repo.Migrations.IndexJobCompensationsCompensatedAt do
  @moduledoc """
  The access path for the retention prune added in #1246.

  Every other read of `job_compensations` is either the exactly-once lookup on the
  unique `job_id` or a human looking at a handful of rows, so this is the only
  other index worth its write cost.
  """

  use Ecto.Migration

  def change do
    create index(:job_compensations, [:compensated_at])
  end
end
