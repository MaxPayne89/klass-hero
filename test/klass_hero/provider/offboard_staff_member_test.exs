defmodule KlassHero.Provider.OffboardStaffMemberTest do
  @moduledoc """
  `offboard_staff_member/1` — ending an employment link *and* taking the person
  off every program they were on (#1292).

  The sibling of `deactivate_staff_member/1`, and deliberately not the same
  operation. Deactivation is a reversible pause that keeps Program Staff
  Assignments alive so Messaging membership survives reactivation. Offboarding is
  the provider saying "this person no longer works here", which has to reach the
  read side: each unassignment stages a `staff_unassigned_from_program` event,
  and that event is the only thing that removes the person from the program's
  conversations.

  Before this command existed, the provider-facing removal was a bare
  `Repo.delete` whose assignments were destroyed by an `on_delete: :delete_all`
  FK — so Postgres vaporised the rows, no event was staged, and the removed staff
  member stayed a conversation participant forever.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.EventTestHelper
  import KlassHero.Factory

  alias KlassHero.Provider
  alias KlassHero.Provider.ProgramStaffAssignment
  alias KlassHero.Provider.StaffMember
  alias KlassHero.Repo
  alias KlassHero.Shared.Domain.Events.Event

  setup do
    setup_test_integration_events()

    provider = insert(:provider_profile_schema)
    judo = insert(:program_schema, provider_id: provider.id)
    chess = insert(:program_schema, provider_id: provider.id)
    staff = insert(:staff_member_schema, provider_id: provider.id)

    clear_integration_events()

    %{provider: provider, judo: judo, chess: chess, staff: staff}
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

  defp reload(%StaffMember{id: id}), do: Repo.get!(StaffMember, id)
  defp reload(%ProgramStaffAssignment{id: id}), do: Repo.get!(ProgramStaffAssignment, id)

  defp staged(event_type) do
    get_published_integration_events()
    |> Enum.filter(&(&1.event_type == event_type))
  end

  describe "offboard_staff_member/1" do
    test "ends the employment link", %{staff: staff} do
      assert {:ok, %{staff_member: offboarded}} = Provider.offboard_staff_member(staff)

      assert offboarded.active == false
      assert reload(staff).active == false
    end

    test "unassigns every program the staff member was on", ctx do
      judo = assign(ctx.judo, ctx.staff)
      chess = assign(ctx.chess, ctx.staff)

      assert {:ok, %{unassigned_count: 2}} = Provider.offboard_staff_member(ctx.staff)

      assert %DateTime{} = reload(judo).unassigned_at
      assert %DateTime{} = reload(chess).unassigned_at
    end

    test "stages one unassignment event per program, plus the deactivation", ctx do
      assign(ctx.judo, ctx.staff)
      assign(ctx.chess, ctx.staff)
      clear_integration_events()

      {:ok, _} = Provider.offboard_staff_member(ctx.staff)

      unassignments = staged(:staff_unassigned_from_program)

      assert length(unassignments) == 2
      assert Enum.map(unassignments, & &1.payload.program_id) |> Enum.sort() == Enum.sort([ctx.judo.id, ctx.chess.id])

      assert_integration_event_published(:staff_member_deactivated, %{staff_member_id: ctx.staff.id})
    end

    test "the unassignment events carry the program conversations' teardown key", ctx do
      user = KlassHero.AccountsFixtures.user_fixture()
      staff = insert(:staff_member_schema, provider_id: ctx.provider.id, user_id: user.id)
      assign(ctx.judo, staff)
      clear_integration_events()

      {:ok, _} = Provider.offboard_staff_member(staff)

      # Messaging skips an event whose staff_user_id is nil, so an unclaimed
      # invite tears down nothing — a claimed one must carry the id.
      assert %Event{payload: %{staff_user_id: staff_user_id}} =
               assert_integration_event_published(:staff_unassigned_from_program)

      assert staff_user_id == user.id
    end

    test "succeeds when the staff member leads a program", ctx do
      {:ok, lead} = Provider.set_lead_instructor(ctx.judo.id, ctx.staff.id, ctx.provider.id)
      assert lead.is_lead_instructor

      assert {:ok, %{unassigned_count: 1}} = Provider.offboard_staff_member(ctx.staff)

      unassigned = reload(lead)
      refute unassigned.is_lead_instructor
      assert %DateTime{} = unassigned.unassigned_at
    end

    test "leaves another staff member's assignments alone", ctx do
      colleague = insert(:staff_member_schema, provider_id: ctx.provider.id)
      theirs = assign(ctx.judo, colleague)
      assign(ctx.chess, ctx.staff)

      {:ok, _} = Provider.offboard_staff_member(ctx.staff)

      assert is_nil(reload(theirs).unassigned_at)
      assert reload(colleague).active
    end

    test "is idempotent — re-offboarding stages nothing", ctx do
      assign(ctx.judo, ctx.staff)
      {:ok, %{staff_member: offboarded}} = Provider.offboard_staff_member(ctx.staff)
      clear_integration_events()

      assert {:ok, %{unassigned_count: 0}} = Provider.offboard_staff_member(offboarded)

      assert get_published_integration_events() == []
    end
  end
end
