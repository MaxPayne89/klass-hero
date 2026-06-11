defmodule KlassHero.Repo.Migrations.AddLastSelectedAtToStaffMembers do
  use Ecto.Migration

  @moduledoc """
  Staff-context switcher (#969): remembers which employment a multi-employer
  staff user last selected. Scope resolution orders active staff rows by this
  timestamp (nulls last), so the selected employment wins across devices.
  Nullable, no backfill — users who never switch fall back to the
  employer-first default ordering.
  """

  def change do
    alter table(:staff_members) do
      add :last_selected_at, :utc_datetime_usec, null: true
    end
  end
end
