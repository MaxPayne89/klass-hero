defmodule KlassHero.Participation.RecordAbsenceTest do
  @moduledoc """
  Marking one child absent by hand, with a reason (#1329).

  The batch path (`complete_session`) absents every straggler at once and records
  no reason and no actor; this is the deliberate, per-child counterpart, and the
  transition row is where the two are told apart.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.AttendanceLogHelper
  import KlassHero.Factory

  alias KlassHero.Accounts.Scope
  alias KlassHero.AccountsFixtures
  alias KlassHero.Participation
  alias KlassHero.Participation.AttendanceTransition
  alias KlassHero.Participation.ParticipationRecord
  alias KlassHero.Provider
  alias KlassHero.ProviderFixtures

  describe "record_absence/3" do
    test "marks a registered child absent" do
      %{record: record} = registered_record()
      scope = AccountsFixtures.admin_scope_fixture()

      assert {:ok, absent} = Participation.record_absence(scope, record.id, reason: "Mum called, sick")

      assert %ParticipationRecord{} = absent
      assert absent.status == :absent
      assert Repo.get!(ParticipationRecord, record.id).status == :absent
    end

    test "records who marked the child absent, and why" do
      %{record: record} = registered_record()
      scope = AccountsFixtures.admin_scope_fixture()

      {:ok, _} = Participation.record_absence(scope, record.id, reason: "Mum called, sick")

      assert %AttendanceTransition{} = transition = only_transition(record.id)
      assert transition.from_status == :registered
      assert transition.to_status == :absent
      assert transition.actor_id == scope.user.id
      assert transition.reason == "Mum called, sick"
    end

    test "a reason is optional, and blank is the same as none" do
      for reason <- [nil, "", "   "] do
        %{record: record} = registered_record()
        scope = AccountsFixtures.admin_scope_fixture()

        assert {:ok, _} = Participation.record_absence(scope, record.id, reason: reason)

        assert only_transition(record.id).reason == nil,
               "a #{inspect(reason)} reason should be stored as nil"
      end
    end

    # Absence stays forward-only from `registered`, exactly as before this feature.
    # A provider undoing a check-in goes through `correct_attendance/3`.
    test "refuses a child who is already checked in or out" do
      for status <- [:checked_in, :checked_out] do
        %{record: record} = registered_record(status: status)
        scope = AccountsFixtures.admin_scope_fixture()

        assert {:error, :invalid_status_transition} =
                 Participation.record_absence(scope, record.id, reason: "too late"),
               "a #{status} child should not be markable absent"

        assert only_transition(record.id) == nil, "a refused write should log nothing"
      end
    end

    test "returns not_found for an unknown record" do
      scope = AccountsFixtures.admin_scope_fixture()

      assert {:error, :not_found} = Participation.record_absence(scope, Ecto.UUID.generate())
    end
  end

  # Mirrors `record_check_in_test.exs`: the write path is the authorization of
  # record (ADR-0017), so a staff member's reach is proven here, not only at the
  # LiveView gate that renders the roster.
  describe "record_absence/3 staff authorization at session grain" do
    test "a staff member on the session but not the program can mark a child absent" do
      %{provider: provider, session: session, record: record} = registered_record()
      staff = ProviderFixtures.staff_member_fixture(%{provider_id: provider.id})
      user = AccountsFixtures.user_fixture()

      assert {:ok, _} =
               Provider.assign_staff_to_session(%{
                 provider_id: provider.id,
                 session_id: session.id,
                 staff_member_id: staff.id
               })

      assert {:ok, absent} =
               Participation.record_absence(
                 %Scope{user: user, staff_member: staff},
                 record.id,
                 reason: "No-show"
               )

      assert absent.status == :absent
      assert only_transition(record.id).actor_id == user.id
    end

    test "a stranger is refused" do
      %{record: record} = registered_record()
      user = AccountsFixtures.user_fixture()

      assert {:error, :unauthorized} =
               Participation.record_absence(%Scope{user: user}, record.id, reason: "No-show")

      assert only_transition(record.id) == nil
    end
  end

  defp registered_record(opts \\ []) do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)
    session = insert(:program_session_schema, program_id: program.id, status: :in_progress)
    child = insert(:child_schema)

    record =
      insert(:participation_record_schema,
        session_id: session.id,
        child_id: child.id,
        status: Keyword.get(opts, :status, :registered)
      )

    %{provider: provider, program: program, session: session, record: record}
  end
end
