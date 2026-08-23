defmodule KlassHero.Repo.Migrations.AddBrandingFieldsToProviders do
  use Ecto.Migration

  # Branding fields for the public provider profile page (#1302, epic #1301).
  # All nullable: every existing provider predates them and stays valid.
  #
  # :text rather than a capped varchar. The length caps live in the changeset,
  # where they surface as a user-visible form error; a DB cap here could only
  # raise 22001 from whatever writes it (#1376).
  def change do
    alter table(:providers) do
      add :tagline, :text
      add :cover_image_url, :text
      add :instagram_url, :text
      add :facebook_url, :text
      add :tiktok_url, :text
      add :youtube_url, :text
      add :linkedin_url, :text
    end
  end
end
