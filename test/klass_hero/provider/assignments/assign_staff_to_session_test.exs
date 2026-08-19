defmodule KlassHero.Provider.Assignments.AssignStaffToSessionTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Provider
  alias KlassHero.Provider.SessionStaffAssignment

  defp setup_session do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)
    session = insert(:program_session_schema, program_id: program.id)
    staff = insert(:staff_member_schema, provider_id: provider.id)

    %{provider: provider, program: program, session: session, staff: staff}
  end

  defp assign(ctx, staff_member_id \\ nil) do
    Provider.assign_staff_to_session(%{
      provider_id: ctx.provider.id,
      session_id: ctx.session.id,
      staff_member_id: staff_member_id || ctx.staff.id
    })
  end

  describe "assign_staff_to_session/1" do
    test "creates an override carrying the session, staff member and provider" do
      ctx = setup_session()

      assert {:ok, %SessionStaffAssignment{} = assignment} = assign(ctx)

      assert assignment.provider_id == ctx.provider.id
      assert assignment.session_id == ctx.session.id
      assert assignment.staff_member_id == ctx.staff.id
      assert %DateTime{} = assignment.assigned_at
      assert is_nil(assignment.unassigned_at)
      refute assignment.is_lead_instructor
    end

    test "records who made the override when a user is supplied" do
      ctx = setup_session()
      user = KlassHero.AccountsFixtures.user_fixture()

      assert {:ok, assignment} =
               Provider.assign_staff_to_session(%{
                 provider_id: ctx.provider.id,
                 session_id: ctx.session.id,
                 staff_member_id: ctx.staff.id,
                 assigned_by_user_id: user.id
               })

      assert assignment.assigned_by_user_id == user.id
    end

    test "refuses a second active assignment of the same staff member" do
      ctx = setup_session()
      {:ok, _first} = assign(ctx)

      assert {:error, :already_assigned} = assign(ctx)
    end

    test "allows re-assignment after the first override was retired" do
      ctx = setup_session()
      {:ok, _first} = assign(ctx)
      {:ok, _retired} = Provider.unassign_staff_from_session(ctx.session.id, ctx.staff.id, ctx.provider.id)

      assert {:ok, _second} = assign(ctx)
    end

    test "a session may carry several overrides — that is what splitting a schedule means" do
      ctx = setup_session()
      other = insert(:staff_member_schema, provider_id: ctx.provider.id)

      assert {:ok, _} = assign(ctx)
      assert {:ok, _} = assign(ctx, other.id)
    end

    # Cross-tenant rejection is asserted module-wide in ownership_guard_test.exs.
    test "a deactivated staff member cannot be newly attached" do
      ctx = setup_session()
      {:ok, _} = Provider.deactivate_staff_member(ctx.staff)

      assert {:error, :not_found} = assign(ctx)
    end

    test "an unknown session is not_found" do
      ctx = setup_session()

      assert {:error, :not_found} =
               Provider.assign_staff_to_session(%{
                 provider_id: ctx.provider.id,
                 session_id: Ecto.UUID.generate(),
                 staff_member_id: ctx.staff.id
               })
    end
  end
end
