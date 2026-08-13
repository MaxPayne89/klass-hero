defmodule KlassHero.Provider.Assignments.ListProgramStaffingTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Provider
  alias KlassHero.Provider.Domain.ReadModels.ProgramStaffing
  alias KlassHero.Repo

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

  describe "list_program_staffing/1" do
    test "returns an empty map for an empty list" do
      assert Provider.list_program_staffing([]) == %{}
    end

    test "omits programs nobody is assigned to" do
      {_provider, program, _staff} = setup_provider_program_staff()

      assert Provider.list_program_staffing([program.id]) == %{}
    end

    test "carries every active member, with the lead among them" do
      {provider, program, lead_staff} = setup_provider_program_staff()
      other_staff = insert(:staff_member_schema, provider_id: provider.id)

      assign(program, other_staff)
      {:ok, _} = Provider.set_lead_instructor(program.id, lead_staff.id, provider.id)

      staffing = Map.fetch!(Provider.list_program_staffing([program.id]), program.id)

      assert %ProgramStaffing{program_id: program_id, member_count: 2} = staffing
      assert program_id == program.id
      assert Enum.sort(staffing.member_ids) == Enum.sort([lead_staff.id, other_staff.id])
      assert staffing.lead.id == lead_staff.id
      assert staffing.lead.name == "#{lead_staff.first_name} #{lead_staff.last_name}"
      assert staffing.lead.headshot_url == lead_staff.headshot_url
    end

    # The state #1310 is about: staffed, but nobody leads. Distinguishable from
    # the omitted-entirely case above only because member_count is non-zero.
    test "returns members with a nil lead when the program is leaderless" do
      {provider, program, staff_a} = setup_provider_program_staff()
      staff_b = insert(:staff_member_schema, provider_id: provider.id)

      assign(program, staff_a)
      assign(program, staff_b)

      staffing = Map.fetch!(Provider.list_program_staffing([program.id]), program.id)

      assert staffing.lead == nil
      assert staffing.member_count == 2
    end

    test "drops the lead flag but keeps the member when the lead is cleared" do
      {provider, program, staff} = setup_provider_program_staff()
      {:ok, _} = Provider.set_lead_instructor(program.id, staff.id, provider.id)
      :ok = Provider.clear_lead_instructor(program.id, provider.id)

      staffing = Map.fetch!(Provider.list_program_staffing([program.id]), program.id)

      assert staffing.lead == nil
      assert staffing.member_ids == [staff.id]
    end

    test "excludes a member who has been unassigned" do
      {provider, program, staff_a} = setup_provider_program_staff()
      staff_b = insert(:staff_member_schema, provider_id: provider.id)

      assign(program, staff_a)
      assign(program, staff_b)
      {:ok, _} = Provider.unassign_staff_from_program(program.id, staff_b.id, provider.id)

      staffing = Map.fetch!(Provider.list_program_staffing([program.id]), program.id)

      assert staffing.member_ids == [staff_a.id]
      assert staffing.member_count == 1
    end

    # Deactivation is how GDPR erasure retires a staff row, and it clears lead
    # flags without unassigning. A deactivated member must not inflate the count
    # the table renders as "+1".
    test "excludes a deactivated member" do
      {provider, program, staff_a} = setup_provider_program_staff()
      staff_b = insert(:staff_member_schema, provider_id: provider.id)

      assign(program, staff_a)
      assign(program, staff_b)

      staff_b |> Ecto.Changeset.change(active: false) |> Repo.update!()

      staffing = Map.fetch!(Provider.list_program_staffing([program.id]), program.id)

      assert staffing.member_ids == [staff_a.id]
      assert staffing.member_count == 1
    end

    test "groups members by program across a batch" do
      {provider, program_a, staff_a} = setup_provider_program_staff()
      program_b = insert(:program_schema, provider_id: provider.id)
      program_c = insert(:program_schema, provider_id: provider.id)
      staff_b = insert(:staff_member_schema, provider_id: provider.id)

      assign(program_a, staff_a)
      assign(program_b, staff_a)
      assign(program_b, staff_b)

      result = Provider.list_program_staffing([program_a.id, program_b.id, program_c.id])

      assert result[program_a.id].member_count == 1
      assert result[program_b.id].member_count == 2
      refute Map.has_key?(result, program_c.id)
    end
  end
end
