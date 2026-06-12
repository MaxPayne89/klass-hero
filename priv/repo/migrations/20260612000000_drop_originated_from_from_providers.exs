defmodule KlassHero.Repo.Migrations.DropOriginatedFromFromProviders do
  @moduledoc """
  Drops the vestigial `providers.originated_from` column (ADR-0005, #970).

  Post-#965/#966 every provider is a deliberate act, so the column was always
  `"direct"` and carried no information. The `"staff_invite"` legacy rows were
  already deleted by `20260609000001_cleanup_legacy_staff_invite_profiles`, which
  runs first and still sees the column.

  Reversible: `down/0` re-adds the column with its original default so a rollback
  restores the schema shape (historical origin data is gone either way).
  """
  use Ecto.Migration

  def up do
    alter table(:providers) do
      remove :originated_from
    end
  end

  def down do
    alter table(:providers) do
      add :originated_from, :string, default: "direct", null: false
    end
  end
end
