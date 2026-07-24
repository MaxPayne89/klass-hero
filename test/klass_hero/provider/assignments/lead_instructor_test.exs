defmodule KlassHero.Provider.Assignments.LeadInstructorTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Provider
  alias KlassHero.Provider.ProgramStaffAssignment
  alias KlassHero.Repo

  defp setup_provider_program_staff do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)
    staff = insert(:staff_member_schema, provider_id: provider.id)
    {provider, program, staff}
  end

  describe "set_lead_instructor/3" do
    test "flags an existing active assignment as lead" do
      {provider, program, staff} = setup_provider_program_staff()

      {:ok, _} =
        Provider.assign_staff_to_program(%{
          provider_id: provider.id,
          program_id: program.id,
          staff_member_id: staff.id
        })

      assert {:ok, %ProgramStaffAssignment{} = lead} =
               Provider.set_lead_instructor(program.id, staff.id, program.provider_id)

      assert lead.is_lead_instructor == true
      assert lead.staff_member_id == staff.id
    end

    test "creates an active assignment when the staff member has none yet" do
      {_provider, program, staff} = setup_provider_program_staff()

      assert {:ok, %ProgramStaffAssignment{} = lead} =
               Provider.set_lead_instructor(program.id, staff.id, program.provider_id)

      assert lead.is_lead_instructor == true
      assert lead.program_id == program.id
      assert lead.staff_member_id == staff.id
      assert is_nil(lead.unassigned_at)
    end

    test "switching the lead clears the previous lead (one lead per program)" do
      {provider, program, _staff} = setup_provider_program_staff()
      staff_a = insert(:staff_member_schema, provider_id: provider.id)
      staff_b = insert(:staff_member_schema, provider_id: provider.id)

      {:ok, _} = Provider.set_lead_instructor(program.id, staff_a.id, program.provider_id)
      {:ok, _} = Provider.set_lead_instructor(program.id, staff_b.id, program.provider_id)

      leads =
        ProgramStaffAssignment
        |> Repo.all()
        |> Enum.filter(&(&1.program_id == program.id and &1.is_lead_instructor))

      assert [only] = leads
      assert only.staff_member_id == staff_b.id
    end

    test "is idempotent when the staff member is already lead" do
      {_provider, program, staff} = setup_provider_program_staff()

      {:ok, first} = Provider.set_lead_instructor(program.id, staff.id, program.provider_id)
      {:ok, second} = Provider.set_lead_instructor(program.id, staff.id, program.provider_id)

      assert first.id == second.id
      assert second.is_lead_instructor == true
    end

    test "returns :not_found when the staff member does not exist" do
      {_provider, program, _staff} = setup_provider_program_staff()

      assert {:error, :not_found} =
               Provider.set_lead_instructor(program.id, Ecto.UUID.generate(), program.provider_id)
    end

    test "rejects a staff member owned by another provider (IDOR guard)" do
      {provider, program, _staff} = setup_provider_program_staff()

      foreign_provider = insert(:provider_profile_schema)
      foreign_staff = insert(:staff_member_schema, provider_id: foreign_provider.id)

      # A competitor's staff must never be attachable to my program — the assignment
      # would render publicly on /programs/:id. Foreign staff = indistinguishable
      # from missing (:not_found), and NO cross-provider assignment row is written.
      assert {:error, :not_found} =
               Provider.set_lead_instructor(program.id, foreign_staff.id, provider.id)

      refute Repo.exists?(from(a in ProgramStaffAssignment, where: a.program_id == ^program.id))
    end
  end

  describe "clear_lead_instructor/1" do
    test "unsets the lead flag but keeps the assignment active" do
      {_provider, program, staff} = setup_provider_program_staff()
      {:ok, _} = Provider.set_lead_instructor(program.id, staff.id, program.provider_id)

      assert :ok = Provider.clear_lead_instructor(program.id)

      [assignment] =
        ProgramStaffAssignment
        |> Repo.all()
        |> Enum.filter(&(&1.program_id == program.id))

      assert assignment.is_lead_instructor == false
      assert is_nil(assignment.unassigned_at)
    end

    test "is a no-op when there is no lead" do
      {_provider, program, _staff} = setup_provider_program_staff()
      assert :ok = Provider.clear_lead_instructor(program.id)
    end
  end

  describe "get_lead_instructor/1" do
    test "returns the lead as a display map" do
      {_provider, program, staff} = setup_provider_program_staff()
      {:ok, _} = Provider.set_lead_instructor(program.id, staff.id, program.provider_id)

      assert %{id: id, name: name, headshot_url: headshot} =
               Provider.get_lead_instructor(program.id)

      assert id == staff.id
      assert name == "#{staff.first_name} #{staff.last_name}"
      assert headshot == staff.headshot_url
    end

    test "returns nil when there is no lead" do
      {_provider, program, _staff} = setup_provider_program_staff()
      assert is_nil(Provider.get_lead_instructor(program.id))
    end
  end

  describe "list_lead_instructors_for_programs/1" do
    test "returns a map keyed by program_id for programs with a lead" do
      {provider, program_a, staff_a} = setup_provider_program_staff()
      program_b = insert(:program_schema, provider_id: provider.id)
      staff_b = insert(:staff_member_schema, provider_id: provider.id)
      program_c = insert(:program_schema, provider_id: provider.id)

      {:ok, _} = Provider.set_lead_instructor(program_a.id, staff_a.id, program_a.provider_id)
      {:ok, _} = Provider.set_lead_instructor(program_b.id, staff_b.id, program_b.provider_id)

      result =
        Provider.list_lead_instructors_for_programs([program_a.id, program_b.id, program_c.id])

      assert result[program_a.id].id == staff_a.id
      assert result[program_b.id].id == staff_b.id
      refute Map.has_key?(result, program_c.id)
    end

    test "returns an empty map for an empty list" do
      assert Provider.list_lead_instructors_for_programs([]) == %{}
    end
  end
end
