defmodule KlassHero.Participation.RecordCheckOutTest do
  @moduledoc """
  Integration tests for RecordCheckOut use case.

  Tests check-out recording for children already checked in.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.AttendanceLogHelper
  import KlassHero.Factory

  alias KlassHero.AccountsFixtures
  alias KlassHero.Participation.ParticipationRecord

  describe "execute/1" do
    test "successfully checks out a checked-in record" do
      session = insert(:program_session_schema, status: :in_progress)
      child = insert(:child_schema)
      scope = AccountsFixtures.admin_scope_fixture()
      check_in_time = DateTime.add(DateTime.utc_now(), -3600, :second)

      record_schema =
        insert(:participation_record_schema,
          session_id: session.id,
          child_id: child.id,
          status: :checked_in,
          check_in_at: check_in_time,
          check_in_by: AccountsFixtures.unconfirmed_user_fixture().id
        )

      assert {:ok, record} =
               KlassHero.Participation.record_check_out(scope, record_schema.id, notes: "Picked up by parent")

      assert %ParticipationRecord{} = record
      assert record.id == record_schema.id
      assert record.status == :checked_out
      assert record.check_out_notes == "Picked up by parent"
      assert record.check_out_by == scope.user.id
      assert %DateTime{} = record.check_out_at
    end

    test "checks out with nil notes when not provided" do
      session = insert(:program_session_schema, status: :in_progress)
      child = insert(:child_schema)
      scope = AccountsFixtures.admin_scope_fixture()
      check_in_time = DateTime.add(DateTime.utc_now(), -3600, :second)

      record_schema =
        insert(:participation_record_schema,
          session_id: session.id,
          child_id: child.id,
          status: :checked_in,
          check_in_at: check_in_time,
          check_in_by: AccountsFixtures.unconfirmed_user_fixture().id
        )

      assert {:ok, record} =
               KlassHero.Participation.record_check_out(scope, record_schema.id)

      assert record.check_out_notes == nil
      assert record.status == :checked_out
    end

    test "returns error when record not found" do
      non_existent_id = Ecto.UUID.generate()
      scope = AccountsFixtures.admin_scope_fixture()

      assert {:error, :not_found} =
               KlassHero.Participation.record_check_out(scope, non_existent_id)
    end

    test "returns error when record is in registered status" do
      session = insert(:program_session_schema, status: :in_progress)
      child = insert(:child_schema)
      scope = AccountsFixtures.admin_scope_fixture()

      record_schema =
        insert(:participation_record_schema,
          session_id: session.id,
          child_id: child.id,
          status: :registered
        )

      assert {:error, :invalid_status_transition} =
               KlassHero.Participation.record_check_out(scope, record_schema.id)
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
               KlassHero.Participation.record_check_out(scope, record_schema.id)
    end

    test "persists check-out to database" do
      session = insert(:program_session_schema, status: :in_progress)
      child = insert(:child_schema)
      scope = AccountsFixtures.admin_scope_fixture()
      check_in_time = DateTime.add(DateTime.utc_now(), -3600, :second)

      record_schema =
        insert(:participation_record_schema,
          session_id: session.id,
          child_id: child.id,
          status: :checked_in,
          check_in_at: check_in_time,
          check_in_by: AccountsFixtures.unconfirmed_user_fixture().id
        )

      {:ok, record} =
        KlassHero.Participation.record_check_out(scope, record_schema.id)

      reloaded =
        KlassHero.Repo.get(
          ParticipationRecord,
          record.id
        )

      assert reloaded.status == :checked_out
      assert %DateTime{} = reloaded.check_out_at
      assert reloaded.check_out_by == scope.user.id
    end
  end

  # Same assertion as its siblings, deliberately (#1329) — see
  # `KlassHero.AttendanceLogHelper`.
  describe "record_check_out/3 attendance log" do
    test "logs the transition, its actor, and the notes as the reason" do
      session = insert(:program_session_schema, status: :in_progress)
      scope = AccountsFixtures.admin_scope_fixture()

      record =
        insert(:participation_record_schema,
          session_id: session.id,
          child_id: insert(:child_schema).id,
          status: :checked_in,
          check_in_at: DateTime.add(DateTime.utc_now(), -3600, :second),
          check_in_by: AccountsFixtures.unconfirmed_user_fixture().id
        )

      {:ok, checked_out} =
        KlassHero.Participation.record_check_out(scope, record.id, notes: "Picked up by parent")

      assert transition = only_transition(record.id)
      assert transition.from_status == :checked_in
      assert transition.to_status == :checked_out
      assert transition.reason == "Picked up by parent"
      assert transition.actor_id == checked_out.check_out_by
      assert abs(DateTime.diff(transition.occurred_at, checked_out.check_out_at)) <= 1
    end
  end
end
