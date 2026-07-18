defmodule KlassHero.Participation.Domain.Events.ParticipationIntegrationEventsTest do
  @moduledoc """
  Tests for ParticipationIntegrationEvents factory module.
  """

  use ExUnit.Case, async: true

  alias KlassHero.Participation.Domain.Events.ParticipationIntegrationEvents

  # ---------------------------------------------------------------------------
  # session_created
  # ---------------------------------------------------------------------------

  describe "session_created/3" do
    test "creates event with correct type, source_context, and entity_type" do
      session_id = Ecto.UUID.generate()

      event =
        ParticipationIntegrationEvents.session_created(session_id, %{
          program_id: Ecto.UUID.generate(),
          session_date: ~D[2026-04-01],
          start_time: ~T[09:00:00],
          end_time: ~T[10:30:00]
        })

      assert event.event_type == :session_created
      assert event.source_context == :participation
      assert event.entity_type == :session
      assert event.entity_id == session_id
    end

    test "base_payload session_id wins over caller-supplied" do
      real_id = Ecto.UUID.generate()

      event =
        ParticipationIntegrationEvents.session_created(real_id, %{
          session_id: "should-be-overridden",
          program_id: Ecto.UUID.generate(),
          session_date: ~D[2026-04-01],
          start_time: ~T[09:00:00],
          end_time: ~T[10:30:00],
          extra: "data"
        })

      assert event.payload.session_id == real_id
      assert event.payload.extra == "data"
    end

    test "raises when required payload keys are missing" do
      session_id = Ecto.UUID.generate()

      assert_raise ArgumentError,
                   ~r/session_created missing required payload keys/,
                   fn ->
                     ParticipationIntegrationEvents.session_created(session_id, %{})
                   end
    end

    test "raises for nil session_id" do
      valid_payload = %{
        program_id: Ecto.UUID.generate(),
        session_date: ~D[2026-04-01],
        start_time: ~T[09:00:00],
        end_time: ~T[10:30:00]
      }

      assert_raise ArgumentError,
                   ~r/requires a non-empty session_id string/,
                   fn -> ParticipationIntegrationEvents.session_created(nil, valid_payload) end
    end

    test "raises for empty string session_id" do
      valid_payload = %{
        program_id: Ecto.UUID.generate(),
        session_date: ~D[2026-04-01],
        start_time: ~T[09:00:00],
        end_time: ~T[10:30:00]
      }

      assert_raise ArgumentError,
                   ~r/requires a non-empty session_id string/,
                   fn -> ParticipationIntegrationEvents.session_created("", valid_payload) end
    end
  end

  # ---------------------------------------------------------------------------
  # session_started
  # ---------------------------------------------------------------------------

  describe "session_started/3" do
    test "creates event with correct type, source_context, and entity_type" do
      session_id = Ecto.UUID.generate()

      event =
        ParticipationIntegrationEvents.session_started(session_id, %{
          program_id: Ecto.UUID.generate()
        })

      assert event.event_type == :session_started
      assert event.source_context == :participation
      assert event.entity_type == :session
      assert event.entity_id == session_id
    end

    test "base_payload session_id wins over caller-supplied" do
      real_id = Ecto.UUID.generate()

      event =
        ParticipationIntegrationEvents.session_started(real_id, %{
          session_id: "should-be-overridden",
          program_id: Ecto.UUID.generate(),
          extra: "data"
        })

      assert event.payload.session_id == real_id
      assert event.payload.extra == "data"
    end

    test "raises when required payload keys are missing" do
      session_id = Ecto.UUID.generate()

      assert_raise ArgumentError,
                   ~r/session_started missing required payload keys/,
                   fn ->
                     ParticipationIntegrationEvents.session_started(session_id, %{})
                   end
    end

    test "raises for nil or empty session_id" do
      valid_payload = %{program_id: Ecto.UUID.generate()}

      assert_raise ArgumentError,
                   ~r/requires a non-empty session_id string/,
                   fn -> ParticipationIntegrationEvents.session_started(nil, valid_payload) end

      assert_raise ArgumentError,
                   ~r/requires a non-empty session_id string/,
                   fn -> ParticipationIntegrationEvents.session_started("", valid_payload) end
    end
  end

  # ---------------------------------------------------------------------------
  # session_completed
  # ---------------------------------------------------------------------------

  describe "session_completed/3" do
    test "creates event with correct type, source_context, and entity_type" do
      session_id = Ecto.UUID.generate()

      event =
        ParticipationIntegrationEvents.session_completed(session_id, %{
          program_id: Ecto.UUID.generate(),
          provider_id: Ecto.UUID.generate(),
          program_title: "Art Class"
        })

      assert event.event_type == :session_completed
      assert event.source_context == :participation
      assert event.entity_type == :session
      assert event.entity_id == session_id
    end

    test "includes provider_id and program_title in payload" do
      session_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()
      program_id = Ecto.UUID.generate()

      event =
        ParticipationIntegrationEvents.session_completed(session_id, %{
          program_id: program_id,
          provider_id: provider_id,
          program_title: "Art Class"
        })

      assert event.payload.provider_id == provider_id
      assert event.payload.program_title == "Art Class"
      assert event.payload.program_id == program_id
      assert event.payload.session_id == session_id
    end

    test "base_payload session_id wins over caller-supplied" do
      real_id = Ecto.UUID.generate()

      event =
        ParticipationIntegrationEvents.session_completed(real_id, %{
          session_id: "should-be-overridden",
          program_id: Ecto.UUID.generate(),
          provider_id: Ecto.UUID.generate(),
          program_title: "Art Class",
          extra: "data"
        })

      assert event.payload.session_id == real_id
      assert event.payload.extra == "data"
    end

    test "raises when provider_id is missing" do
      session_id = Ecto.UUID.generate()

      assert_raise ArgumentError,
                   ~r/session_completed missing required payload keys/,
                   fn ->
                     ParticipationIntegrationEvents.session_completed(session_id, %{
                       program_id: Ecto.UUID.generate(),
                       program_title: "Art Class"
                     })
                   end
    end

    test "raises when program_title is missing" do
      session_id = Ecto.UUID.generate()

      assert_raise ArgumentError,
                   ~r/session_completed missing required payload keys/,
                   fn ->
                     ParticipationIntegrationEvents.session_completed(session_id, %{
                       program_id: Ecto.UUID.generate(),
                       provider_id: Ecto.UUID.generate()
                     })
                   end
    end

    test "raises when all required payload keys are missing" do
      session_id = Ecto.UUID.generate()

      assert_raise ArgumentError,
                   ~r/session_completed missing required payload keys/,
                   fn ->
                     ParticipationIntegrationEvents.session_completed(session_id, %{})
                   end
    end

    test "raises for nil or empty session_id" do
      valid_payload = %{
        program_id: Ecto.UUID.generate(),
        provider_id: Ecto.UUID.generate(),
        program_title: "Art Class"
      }

      assert_raise ArgumentError,
                   ~r/requires a non-empty session_id string/,
                   fn -> ParticipationIntegrationEvents.session_completed(nil, valid_payload) end

      assert_raise ArgumentError,
                   ~r/requires a non-empty session_id string/,
                   fn -> ParticipationIntegrationEvents.session_completed("", valid_payload) end
    end
  end

  # ---------------------------------------------------------------------------
  # child_checked_in
  # ---------------------------------------------------------------------------

  describe "child_checked_in/3" do
    test "creates event with correct type, source_context, and entity_type" do
      record_id = Ecto.UUID.generate()

      event =
        ParticipationIntegrationEvents.child_checked_in(record_id, %{
          session_id: Ecto.UUID.generate(),
          child_id: Ecto.UUID.generate()
        })

      assert event.event_type == :child_checked_in
      assert event.source_context == :participation
      assert event.entity_type == :participation_record
      assert event.entity_id == record_id
    end

    test "base_payload record_id wins over caller-supplied" do
      real_id = Ecto.UUID.generate()

      event =
        ParticipationIntegrationEvents.child_checked_in(real_id, %{
          record_id: "should-be-overridden",
          session_id: Ecto.UUID.generate(),
          child_id: Ecto.UUID.generate(),
          extra: "data"
        })

      assert event.payload.record_id == real_id
      assert event.payload.extra == "data"
    end

    test "raises when required payload keys are missing" do
      record_id = Ecto.UUID.generate()

      assert_raise ArgumentError,
                   ~r/child_checked_in missing required payload keys/,
                   fn ->
                     ParticipationIntegrationEvents.child_checked_in(record_id, %{})
                   end
    end

    test "raises for nil or empty record_id" do
      valid_payload = %{session_id: Ecto.UUID.generate(), child_id: Ecto.UUID.generate()}

      assert_raise ArgumentError,
                   ~r/requires a non-empty record_id string/,
                   fn -> ParticipationIntegrationEvents.child_checked_in(nil, valid_payload) end

      assert_raise ArgumentError,
                   ~r/requires a non-empty record_id string/,
                   fn -> ParticipationIntegrationEvents.child_checked_in("", valid_payload) end
    end
  end

  # ---------------------------------------------------------------------------
  # child_checked_out
  # ---------------------------------------------------------------------------

  describe "child_checked_out/3" do
    test "creates event with correct type, source_context, and entity_type" do
      record_id = Ecto.UUID.generate()

      event =
        ParticipationIntegrationEvents.child_checked_out(record_id, %{
          session_id: Ecto.UUID.generate(),
          child_id: Ecto.UUID.generate()
        })

      assert event.event_type == :child_checked_out
      assert event.source_context == :participation
      assert event.entity_type == :participation_record
      assert event.entity_id == record_id
    end

    test "base_payload record_id wins over caller-supplied" do
      real_id = Ecto.UUID.generate()

      event =
        ParticipationIntegrationEvents.child_checked_out(real_id, %{
          record_id: "should-be-overridden",
          session_id: Ecto.UUID.generate(),
          child_id: Ecto.UUID.generate(),
          extra: "data"
        })

      assert event.payload.record_id == real_id
      assert event.payload.extra == "data"
    end

    test "raises when required payload keys are missing" do
      record_id = Ecto.UUID.generate()

      assert_raise ArgumentError,
                   ~r/child_checked_out missing required payload keys/,
                   fn ->
                     ParticipationIntegrationEvents.child_checked_out(record_id, %{})
                   end
    end

    test "raises for nil or empty record_id" do
      valid_payload = %{session_id: Ecto.UUID.generate(), child_id: Ecto.UUID.generate()}

      assert_raise ArgumentError,
                   ~r/requires a non-empty record_id string/,
                   fn -> ParticipationIntegrationEvents.child_checked_out(nil, valid_payload) end

      assert_raise ArgumentError,
                   ~r/requires a non-empty record_id string/,
                   fn -> ParticipationIntegrationEvents.child_checked_out("", valid_payload) end
    end
  end

  # ---------------------------------------------------------------------------
  # child_marked_absent
  # ---------------------------------------------------------------------------

  describe "child_marked_absent/3" do
    test "creates event with correct type, source_context, and entity_type" do
      record_id = Ecto.UUID.generate()

      event =
        ParticipationIntegrationEvents.child_marked_absent(record_id, %{
          session_id: Ecto.UUID.generate(),
          child_id: Ecto.UUID.generate()
        })

      assert event.event_type == :child_marked_absent
      assert event.source_context == :participation
      assert event.entity_type == :participation_record
      assert event.entity_id == record_id
    end

    test "base_payload record_id wins over caller-supplied" do
      real_id = Ecto.UUID.generate()

      event =
        ParticipationIntegrationEvents.child_marked_absent(real_id, %{
          record_id: "should-be-overridden",
          session_id: Ecto.UUID.generate(),
          child_id: Ecto.UUID.generate(),
          extra: "data"
        })

      assert event.payload.record_id == real_id
      assert event.payload.extra == "data"
    end

    test "raises when required payload keys are missing" do
      record_id = Ecto.UUID.generate()

      assert_raise ArgumentError,
                   ~r/child_marked_absent missing required payload keys/,
                   fn ->
                     ParticipationIntegrationEvents.child_marked_absent(record_id, %{})
                   end
    end

    test "raises for nil or empty record_id" do
      valid_payload = %{session_id: Ecto.UUID.generate(), child_id: Ecto.UUID.generate()}

      assert_raise ArgumentError,
                   ~r/requires a non-empty record_id string/,
                   fn ->
                     ParticipationIntegrationEvents.child_marked_absent(nil, valid_payload)
                   end

      assert_raise ArgumentError,
                   ~r/requires a non-empty record_id string/,
                   fn ->
                     ParticipationIntegrationEvents.child_marked_absent("", valid_payload)
                   end
    end
  end

  # ---------------------------------------------------------------------------
  # session_note_submitted
  # ---------------------------------------------------------------------------

  describe "session_note_submitted/3" do
    test "creates event with correct type, source_context, and entity_type" do
      note_id = Ecto.UUID.generate()

      event =
        ParticipationIntegrationEvents.session_note_submitted(note_id, %{
          participation_record_id: Ecto.UUID.generate(),
          child_id: Ecto.UUID.generate(),
          provider_id: Ecto.UUID.generate()
        })

      assert event.event_type == :session_note_submitted
      assert event.source_context == :participation
      assert event.entity_type == :session_note
      assert event.entity_id == note_id
    end

    test "base_payload note_id wins over caller-supplied" do
      real_id = Ecto.UUID.generate()

      event =
        ParticipationIntegrationEvents.session_note_submitted(real_id, %{
          note_id: "should-be-overridden",
          participation_record_id: Ecto.UUID.generate(),
          child_id: Ecto.UUID.generate(),
          provider_id: Ecto.UUID.generate(),
          extra: "data"
        })

      assert event.payload.note_id == real_id
      assert event.payload.extra == "data"
    end

    test "raises when required payload keys are missing" do
      note_id = Ecto.UUID.generate()

      assert_raise ArgumentError,
                   ~r/session_note_submitted missing required payload keys/,
                   fn ->
                     ParticipationIntegrationEvents.session_note_submitted(note_id, %{})
                   end
    end

    test "raises for nil or empty note_id" do
      valid_payload = %{
        participation_record_id: Ecto.UUID.generate(),
        child_id: Ecto.UUID.generate(),
        provider_id: Ecto.UUID.generate()
      }

      assert_raise ArgumentError,
                   ~r/requires a non-empty note_id string/,
                   fn ->
                     ParticipationIntegrationEvents.session_note_submitted(nil, valid_payload)
                   end

      assert_raise ArgumentError,
                   ~r/requires a non-empty note_id string/,
                   fn ->
                     ParticipationIntegrationEvents.session_note_submitted("", valid_payload)
                   end
    end
  end

  # ---------------------------------------------------------------------------
  # session_note_approved
  # ---------------------------------------------------------------------------

  describe "session_note_approved/3" do
    test "creates event with correct type, source_context, and entity_type" do
      note_id = Ecto.UUID.generate()

      event =
        ParticipationIntegrationEvents.session_note_approved(note_id, %{
          participation_record_id: Ecto.UUID.generate(),
          child_id: Ecto.UUID.generate(),
          provider_id: Ecto.UUID.generate()
        })

      assert event.event_type == :session_note_approved
      assert event.source_context == :participation
      assert event.entity_type == :session_note
      assert event.entity_id == note_id
    end

    test "base_payload note_id wins over caller-supplied" do
      real_id = Ecto.UUID.generate()

      event =
        ParticipationIntegrationEvents.session_note_approved(real_id, %{
          note_id: "should-be-overridden",
          participation_record_id: Ecto.UUID.generate(),
          child_id: Ecto.UUID.generate(),
          provider_id: Ecto.UUID.generate(),
          extra: "data"
        })

      assert event.payload.note_id == real_id
      assert event.payload.extra == "data"
    end

    test "raises when required payload keys are missing" do
      note_id = Ecto.UUID.generate()

      assert_raise ArgumentError,
                   ~r/session_note_approved missing required payload keys/,
                   fn ->
                     ParticipationIntegrationEvents.session_note_approved(note_id, %{})
                   end
    end

    test "raises for nil or empty note_id" do
      valid_payload = %{
        participation_record_id: Ecto.UUID.generate(),
        child_id: Ecto.UUID.generate(),
        provider_id: Ecto.UUID.generate()
      }

      assert_raise ArgumentError,
                   ~r/requires a non-empty note_id string/,
                   fn ->
                     ParticipationIntegrationEvents.session_note_approved(nil, valid_payload)
                   end

      assert_raise ArgumentError,
                   ~r/requires a non-empty note_id string/,
                   fn ->
                     ParticipationIntegrationEvents.session_note_approved("", valid_payload)
                   end
    end
  end

  # ---------------------------------------------------------------------------
  # session_note_rejected
  # ---------------------------------------------------------------------------

  describe "session_note_rejected/3" do
    test "creates event with correct type, source_context, and entity_type" do
      note_id = Ecto.UUID.generate()

      event =
        ParticipationIntegrationEvents.session_note_rejected(note_id, %{
          participation_record_id: Ecto.UUID.generate(),
          child_id: Ecto.UUID.generate(),
          provider_id: Ecto.UUID.generate()
        })

      assert event.event_type == :session_note_rejected
      assert event.source_context == :participation
      assert event.entity_type == :session_note
      assert event.entity_id == note_id
    end

    test "base_payload note_id wins over caller-supplied" do
      real_id = Ecto.UUID.generate()

      event =
        ParticipationIntegrationEvents.session_note_rejected(real_id, %{
          note_id: "should-be-overridden",
          participation_record_id: Ecto.UUID.generate(),
          child_id: Ecto.UUID.generate(),
          provider_id: Ecto.UUID.generate(),
          extra: "data"
        })

      assert event.payload.note_id == real_id
      assert event.payload.extra == "data"
    end

    test "raises when required payload keys are missing" do
      note_id = Ecto.UUID.generate()

      assert_raise ArgumentError,
                   ~r/session_note_rejected missing required payload keys/,
                   fn ->
                     ParticipationIntegrationEvents.session_note_rejected(note_id, %{})
                   end
    end

    test "raises for nil or empty note_id" do
      valid_payload = %{
        participation_record_id: Ecto.UUID.generate(),
        child_id: Ecto.UUID.generate(),
        provider_id: Ecto.UUID.generate()
      }

      assert_raise ArgumentError,
                   ~r/requires a non-empty note_id string/,
                   fn ->
                     ParticipationIntegrationEvents.session_note_rejected(nil, valid_payload)
                   end

      assert_raise ArgumentError,
                   ~r/requires a non-empty note_id string/,
                   fn ->
                     ParticipationIntegrationEvents.session_note_rejected("", valid_payload)
                   end
    end
  end

  describe "session_cancelled/3" do
    test "creates a session_cancelled integration event" do
      event = ParticipationIntegrationEvents.session_cancelled("session-1", %{program_id: "program-1"})

      assert event.event_type == :session_cancelled
      assert event.source_context == :participation
      assert event.entity_type == :session
      assert event.entity_id == "session-1"
      assert event.payload.session_id == "session-1"
      assert event.payload.program_id == "program-1"
    end

    test "raises when session_id is nil" do
      assert_raise ArgumentError, fn ->
        ParticipationIntegrationEvents.session_cancelled(nil, %{program_id: "p"})
      end
    end

    test "raises when program_id is missing" do
      assert_raise ArgumentError, fn ->
        ParticipationIntegrationEvents.session_cancelled("session-1", %{})
      end
    end
  end
end
