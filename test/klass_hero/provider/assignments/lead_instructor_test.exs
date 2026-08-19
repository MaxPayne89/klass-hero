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

    test "returns :not_found when the program does not exist" do
      {provider, _program, staff} = setup_provider_program_staff()

      assert {:error, :not_found} =
               Provider.set_lead_instructor(Ecto.UUID.generate(), staff.id, provider.id)
    end
  end

  # Cross-tenant rejection is asserted module-wide in ownership_guard_test.exs.
  describe "clear_lead_instructor/2" do
    test "unsets the lead flag but keeps the assignment active" do
      {_provider, program, staff} = setup_provider_program_staff()
      {:ok, _} = Provider.set_lead_instructor(program.id, staff.id, program.provider_id)

      assert :ok = Provider.clear_lead_instructor(program.id, program.provider_id)

      [assignment] =
        ProgramStaffAssignment
        |> Repo.all()
        |> Enum.filter(&(&1.program_id == program.id))

      assert assignment.is_lead_instructor == false
      assert is_nil(assignment.unassigned_at)
    end

    test "is a no-op when there is no lead" do
      {_provider, program, _staff} = setup_provider_program_staff()
      assert :ok = Provider.clear_lead_instructor(program.id, program.provider_id)
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

    # An inactive staff member must not be advertised as leading a program —
    # /programs/:id is public. Deactivation is also how GDPR erasure retires a
    # staff row, so this is what keeps "Deleted User" off the public page.
    test "ignores a lead who has been deactivated" do
      {_provider, program, staff} = setup_provider_program_staff()
      {:ok, _} = Provider.set_lead_instructor(program.id, staff.id, program.provider_id)

      deactivate(staff)

      assert is_nil(Provider.get_lead_instructor(program.id))
    end
  end

  defp deactivate(staff) do
    staff
    |> Ecto.Changeset.change(active: false)
    |> Repo.update!()
  end

  describe "set_session_lead_instructor/3 on a session that still inherits" do
    setup do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      session = insert(:program_session_schema, program_id: program.id)

      regulars =
        for _ <- 1..3 do
          staff = insert(:staff_member_schema, provider_id: provider.id)

          {:ok, _} =
            Provider.assign_staff_to_program(%{
              provider_id: provider.id,
              program_id: program.id,
              staff_member_id: staff.id
            })

          staff
        end

      {:ok, provider: provider, program: program, session: session, regulars: regulars}
    end

    test "materializes the roster and flags the target, keeping everyone", ctx do
      [_, promoted, _] = ctx.regulars

      assert {:ok, _} = Provider.set_session_lead_instructor(ctx.session.id, promoted.id, ctx.provider.id)

      staffing = Provider.get_session_staffing(ctx.session.id)

      # Used to be {:error, :not_found}: creating a lone override row would have
      # discarded the other two. Materializing first removes that hazard, so the
      # promotion no longer has to be refused.
      assert staffing.source == :override
      assert Enum.sort(staffing.member_ids) == Enum.sort(Enum.map(ctx.regulars, & &1.id))
      assert staffing.lead.id == promoted.id
    end

    test "steps the copied program lead down rather than leaving two", ctx do
      [old_lead, new_lead, _] = ctx.regulars
      {:ok, _} = Provider.set_lead_instructor(ctx.program.id, old_lead.id, ctx.provider.id)

      assert {:ok, _} = Provider.set_session_lead_instructor(ctx.session.id, new_lead.id, ctx.provider.id)

      assert Provider.get_session_staffing(ctx.session.id).lead.id == new_lead.id
      # The program itself is untouched — only this session moved.
      assert Provider.get_lead_instructor(ctx.program.id).id == old_lead.id
    end

    test "is not_found for someone who is on neither the session nor the program", ctx do
      stranger = insert(:staff_member_schema, provider_id: ctx.provider.id)

      assert {:error, :not_found} =
               Provider.set_session_lead_instructor(ctx.session.id, stranger.id, ctx.provider.id)
    end
  end
end
