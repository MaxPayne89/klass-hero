defmodule KlassHero.Provider.Assignments.GetStaffProgramAccessTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Provider
  alias KlassHero.Provider.Domain.ReadModels.StaffProgramAccess

  defp setup_provider_program_staff do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)
    staff = insert(:staff_member_schema, provider_id: provider.id)
    {provider, program, staff}
  end

  defp assign(program, staff) do
    {:ok, assignment} =
      Provider.assign_staff_to_program(%{
        provider_id: program.provider_id,
        program_id: program.id,
        staff_member_id: staff.id
      })

    assignment
  end

  describe "get_staff_program_access/1" do
    test "carries the program ids the staff member is live-assigned to" do
      {provider, program, staff} = setup_provider_program_staff()
      other_program = insert(:program_schema, provider_id: provider.id)

      assign(program, staff)
      assign(other_program, staff)

      access = Provider.get_staff_program_access(staff.id)

      assert %StaffProgramAccess{staff_member_id: staff_member_id} = access
      assert staff_member_id == staff.id
      assert StaffProgramAccess.authorized?(access, program.id)
      assert StaffProgramAccess.authorized?(access, other_program.id)
    end

    test "drops a program the staff member has been unassigned from" do
      {provider, program, staff} = setup_provider_program_staff()

      assign(program, staff)
      {:ok, _} = Provider.unassign_staff_from_program(program.id, staff.id, provider.id)

      refute StaffProgramAccess.authorized?(Provider.get_staff_program_access(staff.id), program.id)
    end

    test "does not leak a colleague's assignments" do
      {provider, program, colleague} = setup_provider_program_staff()
      staff = insert(:staff_member_schema, provider_id: provider.id)

      assign(program, colleague)

      refute StaffProgramAccess.authorized?(Provider.get_staff_program_access(staff.id), program.id)
    end

    test "authorizes nothing for a staff member with no assignments" do
      {_provider, program, staff} = setup_provider_program_staff()

      access = Provider.get_staff_program_access(staff.id)

      assert %StaffProgramAccess{program_ids: program_ids} = access
      assert MapSet.size(program_ids) == 0
      refute StaffProgramAccess.authorized?(access, program.id)
    end
  end
end
