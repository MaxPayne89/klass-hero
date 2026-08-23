defmodule KlassHero.Participation.RecordCheckInTest do
  @moduledoc """
  Integration tests for RecordCheckIn use case.

  Tests check-in recording for children registered for a session.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.AttendanceLogHelper
  import KlassHero.Factory

  alias KlassHero.Accounts.Scope
  alias KlassHero.AccountsFixtures
  alias KlassHero.Participation.ParticipationRecord
  alias KlassHero.Provider
  alias KlassHero.ProviderFixtures

  describe "execute/1" do
    test "successfully checks in a registered record" do
      session = insert(:program_session_schema, status: :in_progress)
      child = insert(:child_schema)
      scope = AccountsFixtures.admin_scope_fixture()

      record_schema =
        insert(:participation_record_schema,
          session_id: session.id,
          child_id: child.id,
          status: :registered
        )

      assert {:ok, record} =
               KlassHero.Participation.record_check_in(scope, record_schema.id, notes: "Child arrived happy")

      assert %ParticipationRecord{} = record
      assert record.id == record_schema.id
      assert record.status == :checked_in
      assert record.check_in_notes == "Child arrived happy"
      assert record.check_in_by == scope.user.id
      assert record.check_in_at != nil
    end

    test "checks in with nil notes when not provided" do
      session = insert(:program_session_schema, status: :in_progress)
      child = insert(:child_schema)
      scope = AccountsFixtures.admin_scope_fixture()

      record_schema =
        insert(:participation_record_schema,
          session_id: session.id,
          child_id: child.id,
          status: :registered
        )

      assert {:ok, record} =
               KlassHero.Participation.record_check_in(scope, record_schema.id)

      assert record.check_in_notes == nil
      assert record.status == :checked_in
    end

    test "returns error when record not found" do
      non_existent_id = Ecto.UUID.generate()
      scope = AccountsFixtures.admin_scope_fixture()

      assert {:error, :not_found} =
               KlassHero.Participation.record_check_in(scope, non_existent_id)
    end

    test "returns error when record is already checked in" do
      session = insert(:program_session_schema, status: :in_progress)
      child = insert(:child_schema)
      scope = AccountsFixtures.admin_scope_fixture()

      record_schema =
        insert(:participation_record_schema,
          session_id: session.id,
          child_id: child.id,
          status: :checked_in,
          check_in_at: DateTime.utc_now(),
          check_in_by: AccountsFixtures.unconfirmed_user_fixture().id
        )

      assert {:error, :invalid_status_transition} =
               KlassHero.Participation.record_check_in(scope, record_schema.id)
    end

    test "returns error when record is already checked out" do
      session = insert(:program_session_schema, status: :in_progress)
      child = insert(:child_schema)
      scope = AccountsFixtures.admin_scope_fixture()
      check_in_time = DateTime.add(DateTime.utc_now(), -3600, :second)

      record_schema =
        insert(:participation_record_schema,
          session_id: session.id,
          child_id: child.id,
          status: :checked_out,
          check_in_at: check_in_time,
          check_in_by: AccountsFixtures.unconfirmed_user_fixture().id,
          check_out_at: DateTime.utc_now(),
          check_out_by: AccountsFixtures.unconfirmed_user_fixture().id
        )

      assert {:error, :invalid_status_transition} =
               KlassHero.Participation.record_check_in(scope, record_schema.id)
    end

    test "persists check-in to database" do
      session = insert(:program_session_schema, status: :in_progress)
      child = insert(:child_schema)
      scope = AccountsFixtures.admin_scope_fixture()

      record_schema =
        insert(:participation_record_schema,
          session_id: session.id,
          child_id: child.id,
          status: :registered
        )

      {:ok, record} =
        KlassHero.Participation.record_check_in(scope, record_schema.id)

      reloaded =
        KlassHero.Repo.get(
          ParticipationRecord,
          record.id
        )

      assert reloaded.status == :checked_in
      assert reloaded.check_in_at != nil
      assert reloaded.check_in_by == scope.user.id
    end
  end

  # The write path is the authorization of record (ADR-0017), so a staff member's
  # reach has to be proven here and not only at the LiveView gate that shows them
  # the roster. Both of these are invisible to a program-grain check: the first
  # has no program assignment to find, the second still has one (#783).
  describe "execute/1 staff authorization at session grain" do
    test "a staff member on the session but not the program can check a child in" do
      %{provider: provider, session: session, record: record} = staffed_session()
      staff = ProviderFixtures.staff_member_fixture(%{provider_id: provider.id})
      user = AccountsFixtures.user_fixture()

      assert {:ok, _} =
               Provider.assign_staff_to_session(%{
                 provider_id: provider.id,
                 session_id: session.id,
                 staff_member_id: staff.id
               })

      assert {:ok, checked_in} =
               KlassHero.Participation.record_check_in(
                 %Scope{user: user, staff_member: staff},
                 record.id,
                 notes: nil
               )

      assert checked_in.status == :checked_in
      assert checked_in.check_in_by == user.id
    end

    test "a staff member removed from the session is refused, though still on the program" do
      %{provider: provider, program: program, session: session, record: record} = staffed_session()
      staff = assigned_staff(provider, program)
      _colleague = assigned_staff(provider, program)
      user = AccountsFixtures.user_fixture()

      assert {:ok, _} = Provider.unassign_staff_from_session(session.id, staff.id, provider.id)

      assert {:error, :unauthorized} =
               KlassHero.Participation.record_check_in(
                 %Scope{user: user, staff_member: staff},
                 record.id,
                 notes: nil
               )
    end
  end

  # The log is only worth having if every verb writes to it (#1329). Asserting it
  # here, in the same shape as `record_absence_test.exs`, is what catches a later
  # refactor that routes check-in around the shared write path.
  describe "record_check_in/3 attendance log" do
    test "logs the transition, its actor, and the notes as the reason" do
      %{record: record} = staffed_session()
      scope = AccountsFixtures.admin_scope_fixture()

      {:ok, checked_in} =
        KlassHero.Participation.record_check_in(scope, record.id, notes: "Arrived early")

      assert transition = only_transition(record.id)
      assert transition.from_status == :registered
      assert transition.to_status == :checked_in
      assert transition.reason == "Arrived early"

      # The agreement that matters, and the one that is exact: the log and the
      # column name the same actor. The timestamps are two clock reads, so they
      # get a tolerance rather than an equality that would flake on a second
      # boundary.
      assert transition.actor_id == checked_in.check_in_by
      assert abs(DateTime.diff(transition.occurred_at, checked_in.check_in_at)) <= 1
    end

    test "a late arrival logs both legs of the absence" do
      %{record: record} = staffed_session()
      scope = AccountsFixtures.admin_scope_fixture()

      {:ok, _} = KlassHero.Participation.record_absence(scope, record.id, reason: "No-show")

      assert {:ok, checked_in} =
               KlassHero.Participation.record_check_in(scope, record.id, notes: "Arrived 09:20")

      assert checked_in.status == :checked_in

      # Both rows land in the same second, so assert on content, not position.
      legs = record.id |> transitions_for() |> Enum.map(&{&1.from_status, &1.to_status})

      assert length(legs) == 2
      assert {:registered, :absent} in legs
      assert {:absent, :checked_in} in legs
    end
  end

  defp staffed_session do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)
    session = insert(:program_session_schema, program_id: program.id, status: :in_progress)
    child = insert(:child_schema)

    record =
      insert(:participation_record_schema,
        session_id: session.id,
        child_id: child.id,
        status: :registered
      )

    %{provider: provider, program: program, session: session, record: record}
  end

  defp assigned_staff(provider, program) do
    staff = ProviderFixtures.staff_member_fixture(%{provider_id: provider.id})

    ProviderFixtures.program_assignment_fixture(%{
      provider_id: provider.id,
      staff_member_id: staff.id,
      program_id: program.id
    })

    staff
  end
end
