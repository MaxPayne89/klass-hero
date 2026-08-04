defmodule KlassHero.ProgramCatalog.RemainingCapacityTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Enrollment
  alias KlassHero.ProgramCatalog

  describe "remaining_capacity/1" do
    test "returns :unlimited when no policy exists" do
      program = insert(:program_schema)

      assert {:ok, :unlimited} = ProgramCatalog.remaining_capacity(program.id)
    end

    test "returns remaining count when policy has max_enrollment" do
      program = insert(:program_schema)

      {:ok, _policy} =
        Enrollment.set_enrollment_policy(%{
          program_id: program.id,
          max_enrollment: 5
        })

      # Insert 2 active enrollments
      insert(:enrollment_schema, program_id: program.id, status: "pending")
      insert(:enrollment_schema, program_id: program.id, status: "confirmed")

      assert {:ok, 3} = ProgramCatalog.remaining_capacity(program.id)
    end

    test "returns :unlimited when policy has only min_enrollment" do
      program = insert(:program_schema)

      {:ok, _policy} =
        Enrollment.set_enrollment_policy(%{
          program_id: program.id,
          min_enrollment: 5
        })

      assert {:ok, :unlimited} = ProgramCatalog.remaining_capacity(program.id)
    end
  end

  describe "remaining_capacities/1" do
    test "returns capacity map for multiple programs" do
      program_capped = insert(:program_schema)
      program_unlimited = insert(:program_schema)

      {:ok, _policy} =
        Enrollment.set_enrollment_policy(%{
          program_id: program_capped.id,
          max_enrollment: 10
        })

      insert(:enrollment_schema, program_id: program_capped.id, status: "pending")

      result =
        ProgramCatalog.remaining_capacities([program_capped.id, program_unlimited.id])

      assert result[program_capped.id] == 9
      assert result[program_unlimited.id] == :unlimited
    end
  end
end
