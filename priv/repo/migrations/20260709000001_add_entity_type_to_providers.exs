defmodule KlassHero.Repo.Migrations.AddEntityTypeToProviders do
  use Ecto.Migration

  # Providers are vetted along one of two tracks selected by `entity_type`. It is
  # foundational (chosen at registration) and must exist before either track's steps.
  # Existing rows backfill to "individual" — the only track built so far.
  def change do
    alter table(:providers) do
      add :entity_type, :string, null: false, default: "individual"
    end
  end
end
