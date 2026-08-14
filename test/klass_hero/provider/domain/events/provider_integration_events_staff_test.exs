defmodule KlassHero.Provider.Domain.Events.ProviderEventsTest do
  @moduledoc """
  Tests for the ProviderEvents factory module.
  """

  use ExUnit.Case, async: true

  alias KlassHero.Provider.Domain.Events.ProviderEvents
  alias KlassHero.Shared.Domain.Events.Event

  # The provider integration-event factories share one contract: build an event
  # with stable identity fields, let the base payload's id win over any
  # caller-supplied id (while preserving extras), and raise on a blank id. The
  # table drives that shape; rows vary only by the factory function, id field
  # name, and entity_type. Factory-specific payload passthrough is covered by
  # the hand-written tests below.
  @factories [
    %{fun: :staff_member_invited, id: :staff_member_id, entity: :staff_member}
  ]

  for %{fun: fun, id: id, entity: entity} <- @factories do
    describe "#{fun}/3" do
      @fun fun
      @id id
      @entity entity

      test "creates event with correct type, source_context, and entity_type" do
        event = apply(ProviderEvents, @fun, ["id-1"])

        assert %Event{} = event
        assert event.event_type == @fun
        assert event.source_context == :provider
        assert event.entity_type == @entity
        assert event.entity_id == "id-1"
      end

      test "base_payload id wins over caller-supplied and preserves extras" do
        payload = %{@id => "overridden", extra: "data"}
        event = apply(ProviderEvents, @fun, ["real-id", payload])

        assert Map.get(event.payload, @id) == "real-id"
        assert event.payload.extra == "data"
      end

      test "raises for a nil or blank id" do
        for bad_id <- [nil, ""] do
          assert_raise ArgumentError, ~r/requires a non-empty #{@id} string/, fn ->
            apply(ProviderEvents, @fun, [bad_id])
          end
        end
      end
    end
  end

  describe "staff_member_invited/3 payload passthrough" do
    test "includes staff_member_id, provider_id, and email in payload" do
      event =
        ProviderEvents.staff_member_invited("staff-1", %{
          provider_id: "provider-1",
          email: "staff@example.com"
        })

      assert event.payload.staff_member_id == "staff-1"
      assert event.payload.provider_id == "provider-1"
      assert event.payload.email == "staff@example.com"
    end
  end
end
