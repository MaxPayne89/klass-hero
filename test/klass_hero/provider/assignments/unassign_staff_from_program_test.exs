defmodule KlassHero.Provider.Assignments.UnassignStaffFromProgramTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Provider
  alias KlassHero.Provider.ProgramStaffAssignment

  describe "unassign_staff_from_program/2" do
    test "unassigns an active assignment and sets unassigned_at" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      staff = insert(:staff_member_schema, provider_id: provider.id)

      {:ok, _} =
        Provider.assign_staff_to_program(%{
          provider_id: provider.id,
          program_id: program.id,
          staff_member_id: staff.id
        })

      assert {:ok, %ProgramStaffAssignment{} = assignment} =
               Provider.unassign_staff_from_program(program.id, staff.id)

      assert assignment.staff_member_id == staff.id
      assert assignment.program_id == program.id
      assert %DateTime{} = assignment.unassigned_at
    end

    test "returns not_found when no active assignment exists" do
      assert {:error, :not_found} =
               Provider.unassign_staff_from_program(Ecto.UUID.generate(), Ecto.UUID.generate())
    end

    test "returns not_found when assignment was already unassigned" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      staff = insert(:staff_member_schema, provider_id: provider.id)

      {:ok, _} =
        Provider.assign_staff_to_program(%{
          provider_id: provider.id,
          program_id: program.id,
          staff_member_id: staff.id
        })

      assert {:ok, _} = Provider.unassign_staff_from_program(program.id, staff.id)

      # Second unassign on same pair should return not_found (no active assignment)
      assert {:error, :not_found} = Provider.unassign_staff_from_program(program.id, staff.id)
    end
  end
end
