defmodule KlassHero.Repo.Migrations.AddDisabledEmailNotificationsToUsers do
  use Ecto.Migration

  # Stores what a user has switched OFF, not what they have on. Absence is
  # therefore "enabled", so every existing row defaults to receiving
  # notifications with no backfill, and a kind added later is on for everyone
  # until they opt out.
  def change do
    alter table(:users) do
      add :disabled_email_notifications, {:array, :string}, null: false, default: []
    end
  end
end
