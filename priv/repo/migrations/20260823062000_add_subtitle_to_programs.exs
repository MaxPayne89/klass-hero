defmodule KlassHero.Repo.Migrations.AddSubtitleToPrograms do
  use Ecto.Migration

  # Nullable with no default and no backfill: NULL means the provider gave no
  # hook, and the subtitle line simply does not render. Every existing program
  # therefore keeps its current appearance untouched.
  #
  # Capped here, unlike the `program_listings` twin: the write side has a
  # changeset, so the cap becomes a user-visible validation error rather than a
  # Postgres 22001 raised mid-projection (#1376).
  def change do
    alter table(:programs) do
      add :subtitle, :string, size: 150
    end
  end
end
