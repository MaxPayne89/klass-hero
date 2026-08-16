defmodule KlassHero.Participation.RecordCheckInTest do
  @moduledoc """
  Integration tests for RecordCheckIn use case.

  Tests check-in recording for children registered for a session.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.AccountsFixtures
  alias KlassHero.Participation.ParticipationRecord

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
end
