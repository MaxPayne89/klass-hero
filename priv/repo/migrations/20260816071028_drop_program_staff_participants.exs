defmodule KlassHero.Repo.Migrations.DropProgramStaffParticipants do
  use Ecto.Migration

  # Messaging's mirror of Provider's program staffing, unread and unwritten since
  # #1321 (Release A, PR #1351, rolled out 2026-08-14). Provider's
  # `program_staff_assignments` is the source of truth; Messaging reads it through
  # the facade.
  #
  # up/down rather than change: Ecto cannot reverse a table drop. `down` recreates
  # the empty table so a rollback leaves a valid schema. It cannot restore rows —
  # acceptable, because nothing has written since Release A and nothing reads it.
  def up do
    drop table(:program_staff_participants)
  end

  def down do
    create table(:program_staff_participants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :provider_id, :binary_id, null: false
      add :program_id, :binary_id, null: false
      add :staff_user_id, :binary_id, null: false
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:program_staff_participants, [:program_id, :staff_user_id])
    create index(:program_staff_participants, [:provider_id])
    create index(:program_staff_participants, [:staff_user_id])
  end
end
