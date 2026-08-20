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

  describe "get_staff_program_access/1 and Closed Programs (#1082)" do
    test "refuses a program that closed, while still naming it as assigned" do
      {provider, _program, staff} = setup_provider_program_staff()
      closed = insert(:program_schema, provider_id: provider.id, end_date: Date.add(Date.utc_today(), -15))

      assign(closed, staff)

      access = Provider.get_staff_program_access(staff.id)

      refute StaffProgramAccess.authorized?(access, closed.id)
      assert StaffProgramAccess.closed?(access, closed.id)
    end

    test "keeps a program that ended inside the grace window" do
      {provider, _program, staff} = setup_provider_program_staff()
      recent = insert(:program_schema, provider_id: provider.id, end_date: Date.add(Date.utc_today(), -1))

      assign(recent, staff)

      access = Provider.get_staff_program_access(staff.id)

      assert StaffProgramAccess.authorized?(access, recent.id)
      refute StaffProgramAccess.closed?(access, recent.id)
    end

    test "partitions a mixed roster into open and closed" do
      {provider, open, staff} = setup_provider_program_staff()
      closed = insert(:program_schema, provider_id: provider.id, end_date: Date.add(Date.utc_today(), -30))

      assign(open, staff)
      assign(closed, staff)

      access = Provider.get_staff_program_access(staff.id)

      assert access.program_ids == MapSet.new([open.id])
      assert access.closed_program_ids == MapSet.new([closed.id])
    end

    test "reports a program that is not closed as not closed" do
      {_provider, open, staff} = setup_provider_program_staff()

      assign(open, staff)

      refute StaffProgramAccess.closed?(Provider.get_staff_program_access(staff.id), open.id)
    end
  end
end
