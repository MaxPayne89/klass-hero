defmodule KlassHero.Repo.Migrations.AddActivePersonaToUsers do
  use Ecto.Migration

  # Nullable with no default and no backfill: NULL means "never chose", which the
  # read path treats exactly like today's provider > staff > parent precedence.
  # Every existing row therefore keeps its current landing surface untouched.
  def change do
    alter table(:users) do
      add :active_persona, :string
    end
  end
end
