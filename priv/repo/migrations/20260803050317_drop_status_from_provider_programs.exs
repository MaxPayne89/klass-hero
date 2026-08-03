defmodule KlassHero.Repo.Migrations.DropStatusFromProviderPrograms do
  use Ecto.Migration

  # The column was projected as the constant "active" for a status concept
  # Program Catalog never had, and nothing ever read it (#736).
  #
  # up/down rather than change: the original column (20260423224709) is
  # `null: false` with no default, so a generated rollback would fail on every
  # existing row. The default here exists only to make that rollback work.
  def up do
    alter table(:provider_programs) do
      remove :status
    end
  end

  def down do
    alter table(:provider_programs) do
      add :status, :string, null: false, default: "active"
    end
  end
end
