defmodule KlassHero.Participation.Domain.Events.ParticipationEventsTest do
  use ExUnit.Case, async: true

  alias KlassHero.Participation.Domain.Events.ParticipationEvents
  alias KlassHero.Participation.ParticipationRecord
  alias KlassHero.Participation.SessionNote

  # Single source of truth: event_type => entity_type. Every constructor derives
  # its entity_type from here rather than hand-writing one.
  @entity_table [
    {:session_created, :session},
    {:session_started, :session},
    {:session_completed, :session},
    {:roster_seeded, :session},
    {:sessions_generated, :program},
    {:child_checked_in, :participation_record},
    {:child_checked_out, :participation_record},
    {:child_marked_absent, :participation_record},
    {:session_note_submitted, :session_note},
    {:session_note_approved, :session_note},
    {:session_note_rejected, :session_note}
  ]

  describe "entity_type_for/1" do
    for {event_type, entity} <- @entity_table do
      test "#{event_type} => #{entity}" do
        assert ParticipationEvents.entity_type_for(unquote(event_type)) == unquote(entity)
      end
    end

    test "raises on an unregistered event type" do
      assert_raise KeyError, fn -> ParticipationEvents.entity_type_for(:not_an_event) end
    end
  end

  describe "constructors derive entity_type from the registry" do
    test "attendance event carries :participation_record" do
      record = %ParticipationRecord{id: "rec-1", session_id: "sess-1", child_id: "child-1"}
      event = ParticipationEvents.child_checked_in(record, [])

      assert event.event_type == :child_checked_in
      assert event.entity_type == :participation_record
    end

    test "session-note event carries :session_note" do
      note = %SessionNote{
        id: "note-1",
        participation_record_id: "rec-1",
        child_id: "child-1",
        provider_id: "prov-1",
        parent_id: "parent-1"
      }

      event = ParticipationEvents.session_note_submitted(note)

      assert event.event_type == :session_note_submitted
      assert event.entity_type == :session_note
    end
  end
end
