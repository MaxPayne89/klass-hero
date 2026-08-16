defmodule KlassHero.Repo.Migrations.AddSenderRoleToMessages do
  use Ecto.Migration

  # Attribution ("Business via Staff Name") was a live staffing lookup at render time, so
  # deactivating a staff member rewrote every message they had ever sent (#1348). The role is
  # a fact about the sender at send time; `SendMessage` already resolves it to authorize the
  # send, so it is recorded here instead of discarded.
  #
  # Nullable, with no backfill: the live lookup is the only signal available for existing
  # rows, so backfilling would freeze today's answer as history rather than recover the true
  # one. Those rows read `nil` and fall back to the old lookup until retention deletes them.
  #
  # No check constraint: `Ecto.Enum` guards the application path, and a constraint would force
  # a migration for every role added later.
  def change do
    alter table(:messages) do
      add :sender_role, :string
    end
  end
end
