defmodule KlassHero.Repo.Migrations.BackfillLeadInstructorAndDropInstructorColumns do
  @moduledoc """
  Completes the move of the lead instructor to `program_staff_assignments`
  (`is_lead_instructor`, single source of truth). Backfills existing
  `programs.instructor_id` values into lead assignments, then drops the
  denormalised snapshot columns on both `programs` and `program_listings`.

  Supersedes ADR 0002 (ProgramCatalog held its own instructor snapshot).
  Irreversible for data: `down` re-adds the columns but cannot repopulate them.
  """

  use Ecto.Migration

  def up do
    # 1. Promote an EXISTING active assignment to lead where the instructor is
    #    already assigned to the program.
    execute("""
    UPDATE program_staff_assignments a
    SET is_lead_instructor = true
    FROM programs p
    WHERE p.instructor_id IS NOT NULL
      AND a.program_id = p.id
      AND a.staff_member_id = p.instructor_id
      AND a.unassigned_at IS NULL
    """)

    # 2. Create a lead assignment for programs whose instructor has no active
    #    assignment row yet (the ~5 seed-data orphans).
    execute("""
    INSERT INTO program_staff_assignments
      (id, provider_id, program_id, staff_member_id, assigned_at, is_lead_instructor, inserted_at, updated_at)
    SELECT gen_random_uuid(), p.provider_id, p.id, p.instructor_id, now(), true, now(), now()
    FROM programs p
    WHERE p.instructor_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM program_staff_assignments a
        WHERE a.program_id = p.id
          AND a.staff_member_id = p.instructor_id
          AND a.unassigned_at IS NULL
      )
    """)

    # 3. Drop the denormalised snapshots now that the flag is authoritative.
    alter table(:programs) do
      remove :instructor_id
      remove :instructor_name
      remove :instructor_headshot_url
    end

    alter table(:program_listings) do
      remove :instructor_name
      remove :instructor_headshot_url
    end
  end

  def down do
    alter table(:programs) do
      add :instructor_id, :binary_id
      add :instructor_name, :string
      add :instructor_headshot_url, :string
    end

    alter table(:program_listings) do
      add :instructor_name, :string
      add :instructor_headshot_url, :string
    end
  end
end
