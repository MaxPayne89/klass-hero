defmodule KlassHero.Participation.Application.Commands.CompleteSessionTest do
  @moduledoc """
  Integration tests for CompleteSession use case.

  Tests completing an in_progress session and transitioning it to completed.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Participation.ParticipationRecord
  alias KlassHero.Participation.ProgramSession
  alias KlassHero.Participation.Application.Commands.CompleteSession
  alias KlassHero.Participation.ProgramSession

  describe "execute/1" do
    test "successfully completes an in_progress session" do
      session_schema = insert(:program_session_schema, status: :in_progress)

      assert {:ok, session} = CompleteSession.execute(session_schema.id)
      assert %ProgramSession{} = session
      assert session.id == session_schema.id
      assert session.status == :completed
    end

    test "returns error when session not found" do
      non_existent_id = Ecto.UUID.generate()

      assert {:error, :not_found} = CompleteSession.execute(non_existent_id)
    end

    test "returns error when completing a scheduled session" do
      session_schema = insert(:program_session_schema, status: :scheduled)

      assert {:error, :invalid_status_transition} = CompleteSession.execute(session_schema.id)
    end

    test "returns error when completing a completed session" do
      session_schema = insert(:program_session_schema, status: :completed)

      assert {:error, :invalid_status_transition} = CompleteSession.execute(session_schema.id)
    end

    test "returns error when completing a cancelled session" do
      session_schema = insert(:program_session_schema, status: :cancelled)

      assert {:error, :invalid_status_transition} = CompleteSession.execute(session_schema.id)
    end

    test "persists status change to database" do
      session_schema = insert(:program_session_schema, status: :in_progress)

      {:ok, completed_session} = CompleteSession.execute(session_schema.id)

      reloaded =
        KlassHero.Repo.get(
          ProgramSession,
          session_schema.id
        )

      assert reloaded.status == :completed
      assert completed_session.status == :completed
    end

    test "persists registered participants as absent in the database" do
      session_schema = insert(:program_session_schema, status: :in_progress)
      child = insert(:child_schema)

      record =
        insert(:participation_record_schema,
          session_id: session_schema.id,
          child_id: child.id,
          status: :registered
        )

      assert {:ok, _session} = CompleteSession.execute(session_schema.id)

      reloaded = KlassHero.Repo.get(ParticipationRecord, record.id)
      assert reloaded.status == :absent
    end

    test "leaves checked_in and checked_out participants unchanged when completing" do
      session_schema = insert(:program_session_schema, status: :in_progress)
      child1 = insert(:child_schema)
      child2 = insert(:child_schema)

      staff_user = KlassHero.AccountsFixtures.unconfirmed_user_fixture()

      checked_in =
        insert(:participation_record_schema,
          session_id: session_schema.id,
          child_id: child1.id,
          status: :checked_in,
          check_in_at: DateTime.utc_now(),
          check_in_by: staff_user.id
        )

      checked_out =
        insert(:participation_record_schema,
          session_id: session_schema.id,
          child_id: child2.id,
          status: :checked_out,
          check_in_at: DateTime.utc_now(),
          check_in_by: staff_user.id,
          check_out_at: DateTime.utc_now(),
          check_out_by: staff_user.id
        )

      assert {:ok, _session} = CompleteSession.execute(session_schema.id)

      assert KlassHero.Repo.get(ParticipationRecord, checked_in.id).status == :checked_in
      assert KlassHero.Repo.get(ParticipationRecord, checked_out.id).status == :checked_out
    end

    test "marks registered participants as absent when completing" do
      session_schema = insert(:program_session_schema, status: :in_progress)
      child1 = insert(:child_schema)
      child2 = insert(:child_schema)
      child3 = insert(:child_schema)

      staff_user = KlassHero.AccountsFixtures.unconfirmed_user_fixture()

      insert(:participation_record_schema,
        session_id: session_schema.id,
        child_id: child1.id,
        status: :checked_in,
        check_in_at: DateTime.utc_now(),
        check_in_by: staff_user.id
      )

      insert(:participation_record_schema,
        session_id: session_schema.id,
        child_id: child2.id,
        status: :checked_out,
        check_in_at: DateTime.utc_now(),
        check_in_by: staff_user.id,
        check_out_at: DateTime.utc_now(),
        check_out_by: staff_user.id
      )

      insert(:participation_record_schema,
        session_id: session_schema.id,
        child_id: child3.id,
        status: :registered
      )

      assert {:ok, session} = CompleteSession.execute(session_schema.id)
      assert session.status == :completed
    end
  end
end
