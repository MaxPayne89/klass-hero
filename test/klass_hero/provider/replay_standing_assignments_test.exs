defmodule KlassHero.Provider.ReplayStandingAssignmentsTest do
  @moduledoc """
  #1312's replay fires on acceptance, so it only ever reaches staff who accept
  *after* it shipped. Anyone already past that moment keeps the empty
  `program_staff_participants` the nil-`staff_user_id` skip left them with, and
  nothing else re-announces. This is the one-off repair for them.
  """
  use KlassHero.DataCase, async: false

  import KlassHero.EventTestHelper
  import KlassHero.Factory

  alias KlassHero.Provider
  alias KlassHero.Provider.StaffMember

  setup do
    setup_test_integration_events()
    :ok
  end

  describe "replay_standing_assignments/0" do
    test "re-announces a standing assignment for a staff member who already claimed" do
      %{staff: staff, assignment: assignment} = claimed_staff_with_assignment()

      assert {:ok, 1} = replay()

      event = assert_integration_event_published(:staff_assigned_to_program)
      assert event.payload.staff_user_id == staff.user_id
      assert event.payload.program_id == assignment.program_id
      assert event.payload.staff_member_id == staff.id
    end

    test "counts every standing assignment, not every staff member" do
      %{staff: staff, provider: provider} = claimed_staff_with_assignment()

      insert(:program_staff_assignment_schema,
        provider_id: provider.id,
        program_id: insert(:program_schema, provider_id: provider.id).id,
        staff_member_id: staff.id
      )

      assert {:ok, 2} = replay()
      assert_integration_event_count(2)
    end

    # Safe to re-run: the producer re-stages, and every consumer absorbs it —
    # Messaging upserts on {program_id, staff_user_id} and only adds
    # conversations the user is absent from.
    test "is re-runnable — a second pass stages the same replay again" do
      claimed_staff_with_assignment()

      assert {:ok, 1} = replay()
      assert {:ok, 1} = replay()
      assert_integration_event_published(:staff_assigned_to_program)
    end
  end

  describe "replay_standing_assignments/0 — what it leaves alone" do
    test "an unclaimed staff member: replaying a nil user_id repairs nothing" do
      assignment = insert(:program_staff_assignment_schema)
      refute Repo.get!(StaffMember, assignment.staff_member_id).user_id

      assert {:ok, 0} = replay()
      assert_no_integration_events_published()
    end

    test "a retired assignment" do
      %{assignment: assignment} = claimed_staff_with_assignment()

      assignment
      |> Ecto.Changeset.change(unassigned_at: DateTime.utc_now() |> DateTime.truncate(:microsecond))
      |> Repo.update!()

      assert {:ok, 0} = replay()
      assert_no_integration_events_published()
    end

    test "a deactivated staff member" do
      %{staff: staff} = claimed_staff_with_assignment()

      staff
      |> Ecto.Changeset.change(active: false)
      |> Repo.update!()

      assert {:ok, 0} = replay()
      assert_no_integration_events_published()
    end
  end

  # Fixtures stage their own events (:user_registered from every user the
  # provider/staff factories create), so clear between arrange and act —
  # otherwise the counts assert on setup noise rather than on the replay.
  defp replay do
    clear_integration_events()
    Provider.replay_standing_assignments()
  end

  defp claimed_staff_with_assignment do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)

    staff =
      insert(:staff_member_schema,
        provider_id: provider.id,
        user_id: KlassHero.AccountsFixtures.user_fixture().id
      )

    assignment =
      insert(:program_staff_assignment_schema,
        provider_id: provider.id,
        program_id: program.id,
        staff_member_id: staff.id
      )

    %{provider: provider, program: program, staff: staff, assignment: assignment}
  end
end
