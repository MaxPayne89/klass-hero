defmodule KlassHero.Repo.Migrations.AddIsLeadInstructorToProgramStaffAssignments do
  use Ecto.Migration

  @doc """
  Adds the `is_lead_instructor` flag that makes `program_staff_assignments` the
  single source of truth for a program's lead instructor (replacing the
  denormalised `programs.instructor_*` snapshot, dropped in a later migration
  once readers are flipped).

  The partial unique index enforces at most one active lead per program.
  """
  def change do
    alter table(:program_staff_assignments) do
      add :is_lead_instructor, :boolean, null: false, default: false
    end

    create unique_index(:program_staff_assignments, [:program_id],
             where: "is_lead_instructor AND unassigned_at IS NULL",
             name: :program_staff_assignments_single_lead
           )
  end
end
