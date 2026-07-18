defmodule KlassHero.Family.Domain.Events.FamilyIntegrationEventsTest do
  @moduledoc "Tests for the FamilyIntegrationEvents factory module."

  use ExUnit.Case, async: true

  alias KlassHero.Family.Domain.Events.FamilyIntegrationEvents
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  # Every family integration-event factory shares one contract: build an
  # event with stable identity fields (source_context is always :family),
  # let the base payload's id win over any caller-supplied id (while
  # preserving extras), and raise on a blank id. The table drives that
  # shape; rows vary only by the id field name and entity_type.
  @factories [
    %{fun: :child_created, id: :child_id, entity_type: :child},
    %{fun: :child_updated, id: :child_id, entity_type: :child},
    %{fun: :invite_family_ready, id: :invite_id, entity_type: :invite}
  ]

  for %{fun: fun, id: id, entity_type: entity_type} <- @factories do
    describe "#{fun}/3" do
      @fun fun
      @id id
      @entity_type entity_type

      test "builds an integration event with stable identity fields" do
        event = apply(FamilyIntegrationEvents, @fun, ["id-1"])

        assert %IntegrationEvent{} = event
        assert event.event_type == @fun
        assert event.source_context == :family
        assert event.entity_type == @entity_type
        assert event.entity_id == "id-1"
        assert Map.get(event.payload, @id) == "id-1"
      end

      test "base payload id wins over caller-supplied and preserves extras" do
        payload = %{@id => "overridden", extra: "data"}
        event = apply(FamilyIntegrationEvents, @fun, ["real-id", payload])

        assert Map.get(event.payload, @id) == "real-id"
        assert event.payload.extra == "data"
      end

      test "raises for a nil or blank id" do
        for bad_id <- [nil, ""] do
          assert_raise ArgumentError, ~r/requires a non-empty #{@id} string/, fn ->
            apply(FamilyIntegrationEvents, @fun, [bad_id])
          end
        end
      end
    end
  end

  describe "payload passthrough" do
    test "child_created carries parent_id and name fields" do
      child_id = Ecto.UUID.generate()

      event =
        FamilyIntegrationEvents.child_created(child_id, %{
          parent_id: Ecto.UUID.generate(),
          first_name: "Emma",
          last_name: "Johnson"
        })

      assert event.payload.first_name == "Emma"
    end

    test "child_updated carries updated name fields" do
      child_id = Ecto.UUID.generate()

      event =
        FamilyIntegrationEvents.child_updated(child_id, %{
          parent_id: Ecto.UUID.generate(),
          first_name: "Emily",
          last_name: "Johnson"
        })

      assert event.payload.first_name == "Emily"
    end

    test "invite_family_ready carries user_id" do
      invite_id = Ecto.UUID.generate()

      payload = %{
        invite_id: invite_id,
        user_id: Ecto.UUID.generate(),
        child_id: Ecto.UUID.generate(),
        parent_id: Ecto.UUID.generate(),
        program_id: Ecto.UUID.generate()
      }

      event = FamilyIntegrationEvents.invite_family_ready(invite_id, payload)

      assert event.payload.user_id == payload.user_id
    end
  end
end
