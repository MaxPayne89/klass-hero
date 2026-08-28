defmodule KlassHero.Participation.EventsPayloadTest do
  use ExUnit.Case, async: true

  alias KlassHero.Participation.Events
  alias KlassHero.Participation.ParticipationRecord
  alias KlassHero.Participation.ProgramSession
  alias KlassHero.Participation.SessionNote

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
    %SessionNote{
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
    test "sets event_type, entity_id, and entity_type" do
      session = build_session()

      event = Events.session_created(session)

      assert event.event_type == :session_created
      assert event.entity_id == session.id
      assert event.entity_type == :session
    end

    test "payload includes session fields" do
      session = %{build_session() | location: "Gym", max_capacity: 20}

      event = Events.session_created(session)

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

      event = Events.session_started(session)

      assert event.event_type == :session_started
      assert event.entity_id == session.id
      assert event.payload.session_id == session.id
      assert event.payload.program_id == session.program_id
      assert %DateTime{} = event.payload.started_at
    end
  end

  describe "session_completed/2" do
    test "sets event_type and includes completed_at in payload" do
      session = %{build_session() | status: :completed}

      event = Events.session_completed(session)

      assert event.event_type == :session_completed
      assert event.entity_id == session.id
      assert event.payload.session_id == session.id
      assert event.payload.program_id == session.program_id
      assert %DateTime{} = event.payload.completed_at
    end

    test "merges extra_payload into session_completed event" do
      session = %{build_session() | status: :completed}

      event =
        Events.session_completed(session,
          extra_payload: %{provider_id: "prov-1", program_title: "Art Class"}
        )

      assert event.payload.provider_id == "prov-1"
      assert event.payload.program_title == "Art Class"
      assert event.payload.program_id == session.program_id
    end
  end

  describe "roster_seeded/4" do
    test "sets event_type, entity_id, and seeded_count in payload" do
      session_id = Ecto.UUID.generate()
      program_id = Ecto.UUID.generate()

      event = Events.roster_seeded(session_id, program_id, 12)

      assert event.event_type == :roster_seeded
      assert event.entity_id == session_id
      assert event.entity_type == :session
      assert event.payload.session_id == session_id
      assert event.payload.program_id == program_id
      assert event.payload.seeded_count == 12
    end
  end

  describe "session_note_submitted/2" do
    test "sets event_type, entity_id as note id, and entity_type as :session_note" do
      note = build_note()

      event = Events.session_note_submitted(note)

      assert event.event_type == :session_note_submitted
      assert event.entity_id == note.id
      assert event.entity_type == :session_note
    end

    test "payload contains all session note fields" do
      note = build_note()

      event = Events.session_note_submitted(note)

      assert event.payload.note_id == note.id
      assert event.payload.participation_record_id == note.participation_record_id
      assert event.payload.child_id == note.child_id
      assert event.payload.provider_id == note.provider_id
      refute Map.has_key?(event.payload, :parent_id)
    end
  end

  describe "session_note_approved/2" do
    test "sets event_type :session_note_approved with correct payload" do
      note = %{build_note() | status: :approved}

      event = Events.session_note_approved(note)

      assert event.event_type == :session_note_approved
      assert event.entity_id == note.id
      assert event.payload.note_id == note.id
      assert event.payload.provider_id == note.provider_id
    end
  end

  describe "session_note_rejected/2" do
    test "sets event_type :session_note_rejected with correct payload" do
      note = %{build_note() | status: :rejected}

      event = Events.session_note_rejected(note)

      assert event.event_type == :session_note_rejected
      assert event.entity_id == note.id
      assert event.payload.note_id == note.id
      assert event.payload.provider_id == note.provider_id
    end
  end

  describe "child_checked_in/2 with session" do
    test "includes program_id from session in payload" do
      record = build_record()
      session = build_session()

      event = Events.child_checked_in(record, session)

      assert event.payload.program_id == @program_id
    end

    test "preserves all existing payload fields" do
      record = build_record()
      session = build_session()

      event = Events.child_checked_in(record, session)

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

      event = Events.child_checked_out(record, session)

      assert event.payload.program_id == @program_id
    end
  end

  describe "child_marked_absent/2 with session" do
    test "includes program_id from session in payload" do
      record = %{build_record() | status: :absent}
      session = build_session()

      event = Events.child_marked_absent(record, session)

      assert event.payload.program_id == @program_id
    end
  end
end
