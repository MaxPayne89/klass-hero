defmodule KlassHero.Participation.Domain.Events.ParticipationEventsTest do
  use ExUnit.Case, async: true

  alias KlassHero.Participation.Domain.Events.ParticipationEvents
  alias KlassHero.Participation.ParticipationRecord
  alias KlassHero.Participation.SessionNote

  # Single source of truth: event_type => aggregate_type. Renaming an atom here
  # must propagate to constructors (this file) AND subscription topics
  # (participation.ex facade). See #1108.
  @aggregate_table [
    {:session_created, :participation},
    {:session_started, :participation},
    {:session_completed, :participation},
    {:roster_seeded, :participation},
    {:child_checked_in, :participation},
    {:child_checked_out, :participation},
    {:child_marked_absent, :participation},
    {:session_note_submitted, :session_note},
    {:session_note_approved, :session_note},
    {:session_note_rejected, :session_note}
  ]

  describe "aggregate_type_for/1" do
    for {event_type, aggregate} <- @aggregate_table do
      test "#{event_type} => #{aggregate}" do
        assert ParticipationEvents.aggregate_type_for(unquote(event_type)) ==
                 unquote(aggregate)
      end
    end

    test "raises on an unregistered event type" do
      assert_raise KeyError, fn -> ParticipationEvents.aggregate_type_for(:not_an_event) end
    end
  end

  describe "constructors derive aggregate_type from the registry" do
    test "attendance event carries :participation" do
      record = %ParticipationRecord{id: "rec-1", session_id: "sess-1", child_id: "child-1"}
      event = ParticipationEvents.child_checked_in(record, [])

      assert event.event_type == :child_checked_in
      assert event.aggregate_type == :participation
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
      assert event.aggregate_type == :session_note
    end
  end
end
