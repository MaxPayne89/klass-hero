defmodule KlassHero.Provider.Assignments.AssignStaffToSessionTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Provider
  alias KlassHero.Provider.Assignments
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
      other = insert(:staff_member_schema, provider_id: ctx.provider.id)
      {:ok, _first} = assign(ctx)
      # Someone has to stay: removing the session's only member is refused.
      {:ok, _} = assign(ctx, other.id)
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

  describe "assign_staff_to_session/1 on a session that still inherits" do
    defp on_program!(ctx, staff_member) do
      {:ok, _} =
        Provider.assign_staff_to_program(%{
          provider_id: ctx.provider.id,
          program_id: ctx.program.id,
          staff_member_id: staff_member.id
        })

      staff_member
    end

    defp regular_staff(ctx, count) do
      for _ <- 1..count do
        ctx |> then(&insert(:staff_member_schema, provider_id: &1.provider.id)) |> then(&on_program!(ctx, &1))
      end
    end

    test "copies the program roster across and appends, rather than replacing it" do
      ctx = setup_session()
      regulars = regular_staff(ctx, 3)

      assert {:ok, _} = assign(ctx)

      staffing = Provider.get_session_staffing(ctx.session.id)

      assert staffing.source == :override
      assert staffing.member_count == 4
      assert Enum.sort(staffing.member_ids) == Enum.sort([ctx.staff.id | Enum.map(regulars, & &1.id)])
    end

    test "keeps naming the same person on the session card" do
      ctx = setup_session()
      [first | _] = regular_staff(ctx, 3)

      before = Assignments.get_session_attribution(ctx.session.id)
      assert before.staff_id == first.id

      assert {:ok, _} = assign(ctx)

      # Materialized rows share a wall-clock instant, so without the per-row
      # stagger the earliest-active winner would be arbitrary and the card would
      # rename itself for no reason the provider can see.
      assert Assignments.get_session_attribution(ctx.session.id) == before
    end

    test "carries the program lead across, so the session is not left lead-less" do
      ctx = setup_session()
      [lead | _] = regular_staff(ctx, 2)
      {:ok, _} = Provider.set_lead_instructor(ctx.program.id, lead.id, ctx.provider.id)

      assert {:ok, _} = assign(ctx)

      assert %{lead: %{id: lead_id}} = Provider.get_session_staffing(ctx.session.id)
      assert lead_id == lead.id
    end

    test "leaves the program's other sessions inheriting" do
      ctx = setup_session()
      regular_staff(ctx, 2)

      sibling =
        insert(:program_session_schema, program_id: ctx.program.id, session_date: Date.add(Date.utc_today(), 7))

      assert {:ok, _} = assign(ctx)

      assert Provider.get_session_staffing(sibling.id).source == :program
    end

    test "is already_assigned for someone the session already shows via the program" do
      ctx = setup_session()
      [regular | _] = regular_staff(ctx, 2)

      assert {:error, :already_assigned} = assign(ctx, regular.id)
    end
  end
end
