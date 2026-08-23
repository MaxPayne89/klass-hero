defmodule KlassHero.Repo.Migrations.CreateAttendanceTransitions do
  use Ecto.Migration

  # A sidecar to `participation_records`, not a replacement: `status` on the
  # record stays authoritative, and this table answers what the record cannot —
  # who changed it, when, and why (#1329). Every attendance verb appends here.
  #
  # No backfill. Rows before this migration have no recorded history, and an
  # empty log for an old record is honest; a synthesised one would not be.
  def change do
    create table(:attendance_transitions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Cascaded, unlike `actor_id` below: a transition whose record is gone
      # describes nothing, and nothing can join back to it.
      add :record_id,
          references(:participation_records, type: :binary_id, on_delete: :delete_all),
          null: false

      add :from_status, :string, null: false
      add :to_status, :string, null: false

      # Nilified rather than cascaded — the transition outlives the account that
      # made it. NULL also carries meaning: no human did this, i.e. the batch
      # absence that session completion applies to every still-registered child.
      add :actor_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      add :reason, :text
      add :occurred_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    # Serves the only read this table has: the latest transition per record.
    create index(:attendance_transitions, [:record_id, :occurred_at])
  end
end
