defmodule KlassHero.Provider.Assignments.UnassignStaffFromSessionTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Provider
  alias KlassHero.Provider.SessionStaffAssignment

  setup do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)
    session = insert(:program_session_schema, program_id: program.id)
    staff = insert(:staff_member_schema, provider_id: provider.id)

    {:ok, provider: provider, program: program, session: session, staff: staff}
  end

  defp assign!(ctx, staff_member_id \\ nil) do
    {:ok, assignment} =
      Provider.assign_staff_to_session(%{
        provider_id: ctx.provider.id,
        session_id: ctx.session.id,
        staff_member_id: staff_member_id || ctx.staff.id
      })

    assignment
  end

  describe "unassign_staff_from_session/3" do
    test "retires the override and stamps unassigned_at", ctx do
      assign!(ctx)

      assert {:ok, %SessionStaffAssignment{} = retired} =
               Provider.unassign_staff_from_session(ctx.session.id, ctx.staff.id, ctx.provider.id)

      assert %DateTime{} = retired.unassigned_at
      refute SessionStaffAssignment.active?(retired)
    end

    test "is not_found when no active override exists", ctx do
      assert {:error, :not_found} =
               Provider.unassign_staff_from_session(ctx.session.id, ctx.staff.id, ctx.provider.id)
    end

    test "is not_found on a second retire of the same override", ctx do
      assign!(ctx)
      {:ok, _} = Provider.unassign_staff_from_session(ctx.session.id, ctx.staff.id, ctx.provider.id)

      assert {:error, :not_found} =
               Provider.unassign_staff_from_session(ctx.session.id, ctx.staff.id, ctx.provider.id)
    end

    test "a deactivated staff member can still be detached", ctx do
      assign!(ctx)
      {:ok, _} = Provider.deactivate_staff_member(ctx.staff)

      assert {:ok, _} = Provider.unassign_staff_from_session(ctx.session.id, ctx.staff.id, ctx.provider.id)
    end
  end

  describe "unassign_staff_from_session/3 lead guard" do
    setup ctx do
      assign!(ctx)
      {:ok, _lead} = Provider.set_session_lead_instructor(ctx.session.id, ctx.staff.id, ctx.provider.id)
      :ok
    end

    test "refuses to retire the session's lead instructor", ctx do
      assert {:error, :cannot_unassign_lead} =
               Provider.unassign_staff_from_session(ctx.session.id, ctx.staff.id, ctx.provider.id)
    end

    test "allows the retire once the lead has been stepped down", ctx do
      :ok = Provider.clear_session_lead_instructor(ctx.session.id, ctx.provider.id)

      assert {:ok, _} = Provider.unassign_staff_from_session(ctx.session.id, ctx.staff.id, ctx.provider.id)
    end

    test "allows the retire once someone else leads", ctx do
      other = insert(:staff_member_schema, provider_id: ctx.provider.id)
      assign!(ctx, other.id)
      {:ok, _} = Provider.set_session_lead_instructor(ctx.session.id, other.id, ctx.provider.id)

      assert {:ok, _} = Provider.unassign_staff_from_session(ctx.session.id, ctx.staff.id, ctx.provider.id)
    end
  end

  describe "revert_session_to_program_roster/2" do
    test "retires every override so the session inherits the program roster again", ctx do
      other = insert(:staff_member_schema, provider_id: ctx.provider.id)
      assign!(ctx)
      assign!(ctx, other.id)
      {:ok, _} = Provider.set_session_lead_instructor(ctx.session.id, ctx.staff.id, ctx.provider.id)

      # Unlike the per-row retire, this clears the lead too — reverting is a
      # deliberate "this session has no staffing of its own", not a detach.
      assert {:ok, 2} = Provider.revert_session_to_program_roster(ctx.session.id, ctx.provider.id)

      staffing = Provider.get_session_staffing(ctx.session.id)
      assert staffing.source == :program
    end

    test "is a no-op returning zero on a session that carries no overrides", ctx do
      assert {:ok, 0} = Provider.revert_session_to_program_roster(ctx.session.id, ctx.provider.id)
    end

    test "cannot reach another provider's session", ctx do
      other_provider = insert(:provider_profile_schema)
      assign!(ctx)

      assert {:error, :not_found} =
               Provider.revert_session_to_program_roster(ctx.session.id, other_provider.id)
    end
  end
end
