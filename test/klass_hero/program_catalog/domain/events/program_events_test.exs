defmodule KlassHero.ProgramCatalog.Domain.Events.ProgramEventsTest do
  @moduledoc """
  Tests for ProgramEvents factory module.
  """

  use ExUnit.Case, async: true

  alias KlassHero.ProgramCatalog.Domain.Events.ProgramEvents
  alias KlassHero.Shared.Domain.Events.DomainEvent

  # Every factory shares one contract: build a :program DomainEvent, let
  # base_payload's program_id win over any caller-supplied value, and raise
  # on a nil or blank program_id. The table drives that shared shape;
  # factory-specific payload assertions live in their own describe below.
  @factories [:program_created, :program_updated]

  for fun <- @factories do
    describe "#{fun}/3" do
      @fun fun

      test "builds a valid event with default payload" do
        event = apply(ProgramEvents, @fun, ["program-1"])

        assert %DomainEvent{} = event
        assert event.event_type == @fun
        assert event.aggregate_id == "program-1"
        assert event.aggregate_type == :program
        assert event.payload.program_id == "program-1"
      end

      test "base_payload program_id wins over caller-supplied and preserves extras" do
        conflicting_payload = %{program_id: "should-be-overridden", extra: "data"}

        event = apply(ProgramEvents, @fun, ["real-id", conflicting_payload])

        assert event.payload.program_id == "real-id"
        assert event.payload.extra == "data"
      end

      test "raises for a nil or empty program_id" do
        for bad_id <- [nil, ""] do
          assert_raise ArgumentError, fn ->
            apply(ProgramEvents, @fun, [bad_id])
          end
        end
      end
    end
  end

  describe "program_updated/3 payload" do
    test "carries title and price fields" do
      payload = %{title: "Updated Title", price: Decimal.new("200.00")}

      event = ProgramEvents.program_updated("program-1", payload)

      assert event.payload.title == "Updated Title"
      assert event.payload.price == Decimal.new("200.00")
    end

    # Schedule changes ride on :program_updated — the dedicated
    # :program_schedule_updated event was deleted in #1141 as an
    # unconsumed duplicate of this strictly larger payload.
    test "carries meeting day and time fields" do
      event =
        ProgramEvents.program_updated("program-1", %{
          meeting_days: ["Monday", "Wednesday"],
          meeting_start_time: ~T[16:00:00],
          meeting_end_time: ~T[17:30:00]
        })

      assert event.payload.meeting_days == ["Monday", "Wednesday"]
      assert event.payload.meeting_start_time == ~T[16:00:00]
      assert event.payload.meeting_end_time == ~T[17:30:00]
    end
  end
end
