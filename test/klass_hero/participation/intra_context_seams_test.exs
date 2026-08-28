defmodule KlassHero.Participation.IntraContextSeamsTest do
  @moduledoc """
  The functions that are public only because another module inside Participation
  needs them.

  They are grouped rather than scattered because that is what they have in
  common: none is reachable through `KlassHero.Participation`, so none is
  covered by the use-case tests, and each exists to serve exactly one named
  caller in a sibling module. A change that breaks one of these breaks a seam,
  not a feature, and the failure would otherwise surface somewhere unrelated.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.AccountsFixtures
  alias KlassHero.Participation.Attendance
  alias KlassHero.Participation.ParticipationRecord
  alias KlassHero.Participation.ProgramSession
  alias KlassHero.Participation.SessionNotes
  alias KlassHero.Participation.Sessions

  describe "Attendance.authorize_for_record/2 — the ADR-0017 guard" do
    test "grants an admin, whose standing is program-wide" do
      record = insert(:participation_record_schema)

      assert {:ok, :admin} = Attendance.authorize_for_record(AccountsFixtures.admin_scope_fixture(), record)
    end

    test "refuses a scope holding no persona on the session's program" do
      record = insert(:participation_record_schema)
      scope = AccountsFixtures.user_scope_fixture()

      assert {:error, :unauthorized} = Attendance.authorize_for_record(scope, record)
    end

    test "refuses when the record names a session that does not exist" do
      record = %{insert(:participation_record_schema) | session_id: Ecto.UUID.generate()}

      assert {:error, :not_found} = Attendance.authorize_for_record(AccountsFixtures.admin_scope_fixture(), record)
    end
  end

  describe "Attendance.list_records_by_session/1 — for the roster reads" do
    test "returns only the given session's records" do
      session = insert(:program_session_schema)
      other = insert(:program_session_schema)
      mine = insert(:participation_record_schema, session_id: session.id)
      insert(:participation_record_schema, session_id: other.id)

      assert [found] = Attendance.list_records_by_session(session.id)
      assert found.id == mine.id
    end

    test "returns an empty list for a session with no roster" do
      session = insert(:program_session_schema)

      assert [] == Attendance.list_records_by_session(session.id)
    end
  end

  describe "Attendance.mark_roster_absent_for_session/1 — the roster half of completion" do
    test "sweeps registered children to absent and leaves settled ones alone" do
      session = insert(:program_session_schema, status: "in_progress")
      registered = insert(:participation_record_schema, session_id: session.id, status: :registered)

      checked_out =
        insert(:participation_record_schema,
          session_id: session.id,
          status: :checked_out,
          check_in_at: DateTime.utc_now(),
          check_out_at: DateTime.utc_now()
        )

      assert {:ok, events} = Attendance.mark_roster_absent_for_session(session)

      assert length(events) == 1
      assert Repo.get(ParticipationRecord, registered.id).status == :absent
      assert Repo.get(ParticipationRecord, checked_out.id).status == :checked_out
    end

    test "returns no events when nothing is still registered" do
      session = insert(:program_session_schema, status: "in_progress")

      assert {:ok, []} = Attendance.mark_roster_absent_for_session(session)
    end
  end

  describe "Sessions.persist_lifecycle_update/1 — the session half of completion" do
    test "writes a transition already applied in memory" do
      schema = insert(:program_session_schema, status: "in_progress")
      {:ok, completed} = ProgramSession.complete(%{schema | status: :in_progress})

      assert {:ok, persisted} = Sessions.persist_lifecycle_update(completed)
      assert persisted.status == :completed
      assert Repo.get(ProgramSession, schema.id).status == :completed
    end
  end

  describe "Sessions.upcoming_scheduled_session_ids/1 — for the roster backfill" do
    test "returns today's and later scheduled sessions, and nothing else" do
      program = insert(:program_schema)

      today =
        insert(:program_session_schema, program_id: program.id, session_date: Date.utc_today(), status: "scheduled")

      future =
        insert(:program_session_schema,
          program_id: program.id,
          session_date: Date.add(Date.utc_today(), 7),
          status: "scheduled"
        )

      insert(:program_session_schema,
        program_id: program.id,
        session_date: Date.add(Date.utc_today(), -1),
        status: "scheduled"
      )

      insert(:program_session_schema,
        program_id: program.id,
        session_date: Date.utc_today(),
        start_time: ~T[14:00:00],
        end_time: ~T[16:00:00],
        status: "completed"
      )

      ids = Sessions.upcoming_scheduled_session_ids(program.id)

      assert Enum.sort(ids) == Enum.sort([today.id, future.id])
    end
  end

  describe "SessionNotes.list_approved_notes_for_children/1 — for the roster reads" do
    test "groups approved notes by child and omits unapproved ones" do
      approved = insert(:session_note_schema, status: :approved)
      insert(:session_note_schema, status: :pending_approval)

      grouped = SessionNotes.list_approved_notes_for_children([approved.child_id])

      assert [note] = Map.fetch!(grouped, approved.child_id)
      assert note.id == approved.id
    end

    test "returns an empty map for children with no approved notes" do
      assert %{} == SessionNotes.list_approved_notes_for_children([Ecto.UUID.generate()])
    end
  end
end
