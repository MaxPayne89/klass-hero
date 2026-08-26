defmodule KlassHero.Repo.Migrations.DropParentNotificationPreferences do
  use Ecto.Migration

  # DEPLOY ORDERING: the release before this one still carries
  # `field :notification_preferences, :map` on ParentProfile, so its queries name
  # the column. Fly runs migrations while that release is still serving, and
  # `Accounts.Scope.resolve_roles/1` loads a parent profile on every authenticated
  # LiveView mount — so between this statement committing and the new machines
  # taking traffic, those mounts fail with `column does not exist`.
  #
  # Reversible without data loss: the column was castable but no caller ever
  # passed it (every `Family.create_parent_profile/1` call site sends
  # `identity_id` alone), so it is NULL in every row. Rolling back re-adds it
  # with the same type and nullability — last in ordinal position rather than
  # where it was, which nothing depends on because Ecto names every field it
  # selects. See ADR 0022 for why it was dead in the first place.
  def change do
    alter table(:parents) do
      remove :notification_preferences, :map
    end
  end
end
