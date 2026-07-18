defmodule KlassHero.Participation.Domain.Events.ParticipationIntegrationEventsTest do
  @moduledoc "Tests for the ParticipationIntegrationEvents factory module."

  use ExUnit.Case, async: true

  alias KlassHero.Participation.Domain.Events.ParticipationIntegrationEvents, as: Events

  # Every factory shares one contract: build an event with stable identity
  # fields, let the base payload's id win over any caller-supplied id, and raise
  # on missing required keys or a blank id. The table drives that shared shape;
  # factory-specific payload assertions live in their own describe below.
  @factories [
    %{
      fun: :session_created,
      entity: :session,
      id: :session_id,
      valid: %{program_id: "p", session_date: ~D[2026-04-01], start_time: ~T[09:00:00], end_time: ~T[10:30:00]}
    },
    %{fun: :session_started, entity: :session, id: :session_id, valid: %{program_id: "p"}},
    %{
      fun: :session_completed,
      entity: :session,
      id: :session_id,
      valid: %{program_id: "p", provider_id: "pv", program_title: "Art Class"}
    },
    %{fun: :session_cancelled, entity: :session, id: :session_id, valid: %{program_id: "p"}},
    %{fun: :roster_seeded, entity: :session, id: :session_id, valid: %{program_id: "p", seeded_count: 3}},
    %{fun: :child_checked_in, entity: :participation_record, id: :record_id, valid: %{session_id: "s", child_id: "c"}},
    %{fun: :child_checked_out, entity: :participation_record, id: :record_id, valid: %{session_id: "s", child_id: "c"}},
    %{
      fun: :child_marked_absent,
      entity: :participation_record,
      id: :record_id,
      valid: %{session_id: "s", child_id: "c"}
    },
    %{
      fun: :session_note_submitted,
      entity: :session_note,
      id: :note_id,
      valid: %{participation_record_id: "pr", child_id: "c", provider_id: "pv"}
    },
    %{
      fun: :session_note_approved,
      entity: :session_note,
      id: :note_id,
      valid: %{participation_record_id: "pr", child_id: "c", provider_id: "pv"}
    },
    %{
      fun: :session_note_rejected,
      entity: :session_note,
      id: :note_id,
      valid: %{participation_record_id: "pr", child_id: "c", provider_id: "pv"}
    }
  ]

  for %{fun: fun, entity: entity, id: id, valid: valid} <- @factories do
    describe "#{fun}/3" do
      @fun fun
      @entity entity
      @id id
      @valid valid

      test "builds a valid event with stable identity fields" do
        event = apply(Events, @fun, ["id-1", @valid])

        assert event.event_type == @fun
        assert event.source_context == :participation
        assert event.entity_type == @entity
        assert event.entity_id == "id-1"
        assert Map.get(event.payload, @id) == "id-1"
      end

      test "base payload id wins over caller-supplied and preserves extras" do
        payload = @valid |> Map.put(@id, "overridden") |> Map.put(:extra, "data")
        event = apply(Events, @fun, ["real-id", payload])

        assert Map.get(event.payload, @id) == "real-id"
        assert event.payload.extra == "data"
      end

      test "raises when required payload keys are missing" do
        assert_raise ArgumentError, ~r/#{@fun} missing required payload keys/, fn ->
          apply(Events, @fun, ["id-1", %{}])
        end
      end

      test "raises for a nil or blank id" do
        for bad_id <- [nil, ""] do
          assert_raise ArgumentError, ~r/requires a non-empty #{@id} string/, fn ->
            apply(Events, @fun, [bad_id, @valid])
          end
        end
      end
    end
  end

  describe "session_completed/3 payload" do
    test "carries provider_id, program_title, program_id, and session_id" do
      event =
        Events.session_completed("s1", %{
          program_id: "p1",
          provider_id: "pv1",
          program_title: "Art Class"
        })

      assert event.payload.provider_id == "pv1"
      assert event.payload.program_title == "Art Class"
      assert event.payload.program_id == "p1"
      assert event.payload.session_id == "s1"
    end
  end
end
