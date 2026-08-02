defmodule KlassHero.Shared.Adapters.Driven.Persistence.Schemas.JobCompensation do
  @moduledoc """
  Ecto schema for the `job_compensations` ledger.

  Internal to `JobCompensationRepository` — not a domain model. Each row records
  that a permanently-dead Oban job has had its compensating fact established, so
  the sweep stops reconsidering it. Identity is `job_id`; there is no synthetic
  primary key and no association to `oban_jobs`, whose rows the Pruner deletes on
  a schedule of its own.
  """

  use Ecto.Schema

  @primary_key false
  schema "job_compensations" do
    field :job_id, :integer
    field :worker, :string
    field :compensated_at, :utc_datetime_usec
  end
end
