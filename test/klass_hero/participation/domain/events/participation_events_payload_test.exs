defmodule KlassHero.Participation.Domain.Events.ParticipationEventsPayloadTest do
  use ExUnit.Case, async: true

  alias KlassHero.Participation.BehavioralNote
  alias KlassHero.Participation.Domain.Events.ParticipationEvents
  alias KlassHero.Participation.ParticipationRecord
  alias KlassHero.Participation.ProgramSession

  @program_id Ecto.UUID.generate()

  defp build_record do
    %ParticipationRecord{
      id: Ecto.UUID.generate(),
      session_id: Ecto.UUID.generate(),
      child_id: Ecto.UUID.generate(),
      status: :checked_in,
      check_in_by: Ecto.UUID.generate(),
      check_in_at: DateTime.utc_now(),
      check_in_notes: nil
    }
  end

  defp build_session do
    %ProgramSession{
      id: Ecto.UUID.generate(),
      program_id: @program_id,
      session_date: Date.utc_today(),
      start_time: ~T[09:00:00],
      end_time: ~T[12:00:00],
      status: :in_progress
    }
  end

  defp build_note do
    %BehavioralNote{
      id: Ecto.UUID.generate(),
      participation_record_id: Ecto.UUID.generate(),
      child_id: Ecto.UUID.generate(),
      provider_id: Ecto.UUID.generate(),
      parent_id: Ecto.UUID.generate(),
      content: "Disruptive during circle time",
      status: :pending_approval
    }
  end

  describe "session_created/2" do
    test "sets event_type, aggregate_id, and aggregate_type" do
      session = build_session()

      event = ParticipationEvents.session_created(session)

      assert event.event_type == :session_created
      assert event.aggregate_id == session.id
      assert event.aggregate_type == :participation
    end

    test "payload includes session fields" do
      session = %{build_session() | location: "Gym", max_capacity: 20}

      event = ParticipationEvents.session_created(session)

      assert event.payload.session_id == session.id
      assert event.payload.program_id == session.program_id
      assert event.payload.session_date == session.session_date
      assert event.payload.start_time == session.start_time
      assert event.payload.end_time == session.end_time
      assert event.payload.location == "Gym"
      assert event.payload.max_capacity == 20
    end
  end

  describe "session_started/2" do
    test "sets event_type and includes started_at in payload" do
      session = build_session()

      event = ParticipationEvents.session_started(session)

      assert event.event_type == :session_started
      assert event.aggregate_id == session.id
      assert event.payload.session_id == session.id
      assert event.payload.program_id == session.program_id
      assert %DateTime{} = event.payload.started_at
    end
  end

  describe "session_completed/2" do
    test "sets event_type and includes completed_at in payload" do
      session = %{build_session() | status: :completed}

      event = ParticipationEvents.session_completed(session)

      assert event.event_type == :session_completed
      assert event.aggregate_id == session.id
      assert event.payload.session_id == session.id
      assert event.payload.program_id == session.program_id
      assert %DateTime{} = event.payload.completed_at
    end

    test "merges extra_payload into session_completed event" do
      session = %{build_session() | status: :completed}

      event =
        ParticipationEvents.session_completed(session,
          extra_payload: %{provider_id: "prov-1", program_title: "Art Class"}
        )

      assert event.payload.provider_id == "prov-1"
      assert event.payload.program_title == "Art Class"
      assert event.payload.program_id == session.program_id
    end
  end

  describe "roster_seeded/4" do
    test "sets event_type, aggregate_id, and seeded_count in payload" do
      session_id = Ecto.UUID.generate()
      program_id = Ecto.UUID.generate()

      event = ParticipationEvents.roster_seeded(session_id, program_id, 12)

      assert event.event_type == :roster_seeded
      assert event.aggregate_id == session_id
      assert event.aggregate_type == :participation
      assert event.payload.session_id == session_id
      assert event.payload.program_id == program_id
      assert event.payload.seeded_count == 12
    end
  end

  describe "behavioral_note_submitted/2" do
    test "sets event_type, aggregate_id as note id, and aggregate_type as :behavioral_note" do
      note = build_note()

      event = ParticipationEvents.behavioral_note_submitted(note)

      assert event.event_type == :behavioral_note_submitted
      assert event.aggregate_id == note.id
      assert event.aggregate_type == :behavioral_note
    end

    test "payload contains all behavioral note fields" do
      note = build_note()

      event = ParticipationEvents.behavioral_note_submitted(note)

      assert event.payload.note_id == note.id
      assert event.payload.participation_record_id == note.participation_record_id
      assert event.payload.child_id == note.child_id
      assert event.payload.provider_id == note.provider_id
      assert event.payload.parent_id == note.parent_id
    end
  end

  describe "behavioral_note_approved/2" do
    test "sets event_type :behavioral_note_approved with correct payload" do
      note = %{build_note() | status: :approved}

      event = ParticipationEvents.behavioral_note_approved(note)

      assert event.event_type == :behavioral_note_approved
      assert event.aggregate_id == note.id
      assert event.payload.note_id == note.id
      assert event.payload.provider_id == note.provider_id
    end
  end

  describe "behavioral_note_rejected/2" do
    test "sets event_type :behavioral_note_rejected with correct payload" do
      note = %{build_note() | status: :rejected}

      event = ParticipationEvents.behavioral_note_rejected(note)

      assert event.event_type == :behavioral_note_rejected
      assert event.aggregate_id == note.id
      assert event.payload.note_id == note.id
      assert event.payload.provider_id == note.provider_id
    end
  end

  describe "child_checked_in/2 with session" do
    test "includes program_id from session in payload" do
      record = build_record()
      session = build_session()

      event = ParticipationEvents.child_checked_in(record, session)

      assert event.payload.program_id == @program_id
    end

    test "preserves all existing payload fields" do
      record = build_record()
      session = build_session()

      event = ParticipationEvents.child_checked_in(record, session)

      assert event.payload.record_id == record.id
      assert event.payload.session_id == record.session_id
      assert event.payload.child_id == record.child_id
    end
  end

  describe "child_checked_out/2 with session" do
    test "includes program_id from session in payload" do
      record = %{
        build_record()
        | status: :checked_out,
          check_out_by: Ecto.UUID.generate(),
          check_out_at: DateTime.utc_now()
      }

      session = build_session()

      event = ParticipationEvents.child_checked_out(record, session)

      assert event.payload.program_id == @program_id
    end
  end

  describe "child_marked_absent/2 with session" do
    test "includes program_id from session in payload" do
      record = %{build_record() | status: :absent}
      session = build_session()

      event = ParticipationEvents.child_marked_absent(record, session)

      assert event.payload.program_id == @program_id
    end
  end
end
