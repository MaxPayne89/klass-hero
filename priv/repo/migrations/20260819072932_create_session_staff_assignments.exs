defmodule KlassHero.Repo.Migrations.CreateSessionStaffAssignments do
  use Ecto.Migration

  def change do
    create table(:session_staff_assignments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :provider_id, references(:providers, type: :binary_id, on_delete: :delete_all),
        null: false

      add :session_id, references(:program_sessions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :staff_member_id, references(:staff_members, type: :binary_id, on_delete: :delete_all),
        null: false

      # Who made the override, for the audit trail. Nilified rather than cascading:
      # the assignment outlives the account that created it.
      add :assigned_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      add :assigned_at, :utc_datetime_usec, null: false
      add :unassigned_at, :utc_datetime_usec
      add :is_lead_instructor, :boolean, null: false, default: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:session_staff_assignments, [:provider_id])
    create index(:session_staff_assignments, [:session_id])
    create index(:session_staff_assignments, [:staff_member_id])

    create unique_index(:session_staff_assignments, [:session_id, :staff_member_id],
             where: "unassigned_at IS NULL",
             name: :session_staff_assignments_active_unique
           )

    create unique_index(:session_staff_assignments, [:session_id],
             where: "is_lead_instructor AND unassigned_at IS NULL",
             name: :session_staff_assignments_single_lead
           )
  end
end
