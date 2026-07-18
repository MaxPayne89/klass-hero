defmodule KlassHero.Repo.Migrations.AddProgramIdStatusIndexToProviderSessionDetails do
  use Ecto.Migration

  @moduledoc """
  Staff assign/unassign projection handlers update rows `where program_id == ^id
  and status == :scheduled`. Both existing indexes lead with `provider_id`, which
  isn't in that predicate, forcing a scan of the read table on every assignment.
  """

  def change do
    create index(:provider_session_details, [:program_id, :status])
  end
end
