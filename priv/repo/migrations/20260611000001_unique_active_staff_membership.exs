defmodule KlassHero.Repo.Migrations.UniqueActiveStaffMembership do
  use Ecto.Migration

  alias KlassHero.Release.DedupActiveStaffMemberships

  @moduledoc """
  Race backstop for self-staffing (#969 review): one ACTIVE linked membership
  per (provider_id, user_id). Multi-employer staff are unaffected (different
  provider_id); unlinked display-only rows are unaffected (user_id IS NULL).

  Deduplicates first — transform lives in DedupActiveStaffMemberships so it is
  unit-tested; it deactivates (never deletes) all but the newest duplicate.
  """

  def up do
    {:ok, _counts} = DedupActiveStaffMemberships.run(repo())

    create unique_index(:staff_members, [:provider_id, :user_id],
             where: "active = true AND user_id IS NOT NULL",
             name: :staff_members_active_provider_user_index
           )
  end

  def down do
    drop index(:staff_members, [:provider_id, :user_id],
           name: :staff_members_active_provider_user_index
         )
  end
end
