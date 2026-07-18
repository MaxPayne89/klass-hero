defmodule KlassHero.ProgramCatalog.Domain.Events.ProgramCatalogIntegrationEventsTest do
  @moduledoc """
  Tests for ProgramCatalogIntegrationEvents factory module.
  """

  use ExUnit.Case, async: true

  alias KlassHero.ProgramCatalog.Domain.Events.ProgramCatalogIntegrationEvents, as: Events

  # Both factories share one contract: build a :program_catalog integration
  # event with stable identity fields, let base_payload's program_id win over
  # any caller-supplied value, and raise on a nil or blank program_id.
  @factories [:program_created, :program_updated]

  for fun <- @factories do
    describe "#{fun}/3" do
      @fun fun

      test "creates event with correct type, source_context, and entity_type" do
        event = apply(Events, @fun, ["prog-1"])

        assert event.event_type == @fun
        assert event.source_context == :program_catalog
        assert event.entity_type == :program
        assert event.entity_id == "prog-1"
      end

      test "base_payload program_id wins over caller-supplied program_id" do
        conflicting_payload = %{program_id: "should-be-overridden", extra: "data"}

        event = apply(Events, @fun, ["real-id", conflicting_payload])

        assert event.payload.program_id == "real-id"
        assert event.payload.extra == "data"
      end

      test "raises for a nil or empty program_id" do
        for bad_id <- [nil, ""] do
          assert_raise ArgumentError, ~r/requires a non-empty program_id string/, fn ->
            apply(Events, @fun, [bad_id])
          end
        end
      end
    end
  end
end
