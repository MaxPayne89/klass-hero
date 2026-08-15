defmodule KlassHero.Repo.Migrations.AddFailureCodeToBulkEnrollmentInvites do
  use Ecto.Migration

  # Replaces `error_details`, which held a provider-facing English sentence written by a
  # background process that has no reader's locale in scope (#1340). The old column stays
  # so invites that failed before this migration still read back their reason; nothing
  # writes it any more, and it can be dropped once no live row carries one.
  #
  # No check constraint on `failure_code`: `Ecto.Enum` guards the application path, and a
  # constraint would force a migration for every code added later.
  def change do
    alter table(:bulk_enrollment_invites) do
      add :failure_code, :string
      add :failure_context, :map
    end
  end
end
