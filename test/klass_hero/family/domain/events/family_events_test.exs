defmodule KlassHero.Family.Domain.Events.FamilyEventsTest do
  @moduledoc "Tests for the FamilyEvents factory module."

  use ExUnit.Case, async: true

  alias KlassHero.Family.Domain.Events.FamilyEvents
  alias KlassHero.Shared.Domain.Events.DomainEvent

  # Every family domain-event factory shares one contract: build a domain
  # event with stable identity fields, let the base payload's id win over any
  # caller-supplied id (while preserving extras), and raise on a blank id.
  # The table drives that shape; rows vary only by the id field name, the
  # aggregate_type, and (for child_data_anonymized) default criticality.
  @factories [
    %{fun: :child_created, id: :child_id, aggregate_type: :child, critical: false},
    %{fun: :child_updated, id: :child_id, aggregate_type: :child, critical: false},
    %{fun: :child_data_anonymized, id: :child_id, aggregate_type: :child, critical: true},
    %{fun: :invite_family_ready, id: :invite_id, aggregate_type: :invite, critical: false}
  ]

  for %{fun: fun, id: id, aggregate_type: aggregate_type, critical: critical} <- @factories do
    describe "#{fun}/3" do
      @fun fun
      @id id
      @aggregate_type aggregate_type
      @critical critical

      test "builds a domain event with the right type, aggregate, and criticality" do
        event = apply(FamilyEvents, @fun, ["id-1"])

        assert %DomainEvent{} = event
        assert event.event_type == @fun
        assert event.aggregate_id == "id-1"
        assert event.aggregate_type == @aggregate_type
        assert Map.get(event.payload, @id) == "id-1"
        assert DomainEvent.critical?(event) == @critical
      end

      test "base payload id wins over caller-supplied and preserves extras" do
        payload = %{@id => "overridden", extra: "data"}
        event = apply(FamilyEvents, @fun, ["real-id", payload])

        assert Map.get(event.payload, @id) == "real-id"
        assert event.payload.extra == "data"
      end

      test "raises for a nil or blank id" do
        for bad_id <- [nil, ""] do
          assert_raise ArgumentError, ~r/requires a non-empty #{@id} string/, fn ->
            apply(FamilyEvents, @fun, [bad_id])
          end
        end
      end
    end
  end

  describe "payload passthrough" do
    test "child_created carries parent_id and name fields" do
      child_id = Ecto.UUID.generate()

      event =
        FamilyEvents.child_created(child_id, %{
          parent_id: Ecto.UUID.generate(),
          first_name: "Emma",
          last_name: "Johnson"
        })

      assert event.payload.first_name == "Emma"
      assert event.payload.last_name == "Johnson"
    end

    test "child_updated carries updated name fields" do
      child_id = Ecto.UUID.generate()

      event =
        FamilyEvents.child_updated(child_id, %{
          parent_id: Ecto.UUID.generate(),
          first_name: "Emily",
          last_name: "Johnson"
        })

      assert event.payload.first_name == "Emily"
    end

    test "invite_family_ready carries user_id, child_id, parent_id, and program_id" do
      invite_id = Ecto.UUID.generate()

      payload = %{
        invite_id: invite_id,
        user_id: Ecto.UUID.generate(),
        child_id: Ecto.UUID.generate(),
        parent_id: Ecto.UUID.generate(),
        program_id: Ecto.UUID.generate()
      }

      event = FamilyEvents.invite_family_ready(invite_id, payload)

      assert event.payload.user_id == payload.user_id
      assert event.payload.child_id == payload.child_id
      assert event.payload.parent_id == payload.parent_id
      assert event.payload.program_id == payload.program_id
    end
  end
end
