defmodule KlassHero.Repo.Migrations.AddEntityTypeToProviders do
  use Ecto.Migration

  def change do
    alter table(:providers) do
      add :entity_type, :string, null: false, default: "individual"
    end
  end
end
