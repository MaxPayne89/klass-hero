defmodule KlassHero.Provider.Assignments.AssignStaffToProgramTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Provider
  alias KlassHero.Provider.ProgramStaffAssignment

  describe "assign_staff_to_program/1" do
    test "creates assignment and returns the flat struct" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      staff = insert(:staff_member_schema, provider_id: provider.id)

      assert {:ok, %ProgramStaffAssignment{} = assignment} =
               Provider.assign_staff_to_program(%{
                 provider_id: provider.id,
                 program_id: program.id,
                 staff_member_id: staff.id
               })

      assert assignment.provider_id == provider.id
      assert assignment.program_id == program.id
      assert assignment.staff_member_id == staff.id
      assert %DateTime{} = assignment.assigned_at
      assert is_nil(assignment.unassigned_at)
    end

    test "returns already_assigned for duplicate active assignment" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      staff = insert(:staff_member_schema, provider_id: provider.id)

      attrs = %{
        provider_id: provider.id,
        program_id: program.id,
        staff_member_id: staff.id
      }

      assert {:ok, _} = Provider.assign_staff_to_program(attrs)
      assert {:error, :already_assigned} = Provider.assign_staff_to_program(attrs)
    end

    test "returns not_found when staff member does not exist" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)

      assert {:error, :not_found} =
               Provider.assign_staff_to_program(%{
                 provider_id: provider.id,
                 program_id: program.id,
                 staff_member_id: Ecto.UUID.generate()
               })
    end
  end
end
