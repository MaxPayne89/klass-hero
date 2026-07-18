defmodule KlassHero.Accounts.Domain.Events.AccountsIntegrationEventsTest do
  @moduledoc "Tests for the AccountsIntegrationEvents factory module."

  use ExUnit.Case, async: true

  alias KlassHero.Accounts.Domain.Events.AccountsIntegrationEvents, as: Events
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  # Every accounts integration-event factory shares one contract: build a critical
  # event with stable identity fields, let the base payload's id win over any
  # caller-supplied id (while preserving extras), allow criticality to be lowered
  # via opts, and raise on a blank id. The table drives that shape; rows vary only
  # by the id field name and entity_type.
  @factories [
    %{fun: :user_registered, id: :user_id, entity: :user},
    %{fun: :user_anonymized, id: :user_id, entity: :user},
    %{fun: :user_confirmed, id: :user_id, entity: :user},
    %{fun: :staff_invitation_sent, id: :staff_member_id, entity: :staff_member},
    %{fun: :staff_invitation_failed, id: :staff_member_id, entity: :staff_member},
    %{fun: :staff_user_registered, id: :user_id, entity: :user}
  ]

  for %{fun: fun, id: id, entity: entity} <- @factories do
    describe "#{fun}/3" do
      @fun fun
      @id id
      @entity entity

      test "builds a critical event with stable identity fields" do
        event = apply(Events, @fun, ["id-1"])

        assert %IntegrationEvent{} = event
        assert event.event_type == @fun
        assert event.source_context == :accounts
        assert event.entity_type == @entity
        assert event.entity_id == "id-1"
        assert Map.get(event.payload, @id) == "id-1"
        assert IntegrationEvent.critical?(event)
      end

      test "base payload id wins over caller-supplied and preserves extras" do
        payload = %{@id => "overridden", :extra => "data"}
        event = apply(Events, @fun, ["real-id", payload])

        assert Map.get(event.payload, @id) == "real-id"
        assert event.payload.extra == "data"
      end

      test "allows overriding criticality via opts" do
        event = apply(Events, @fun, ["id-1", %{}, [criticality: :normal]])

        refute IntegrationEvent.critical?(event)
      end

      test "raises for a nil or blank id" do
        for bad_id <- [nil, ""] do
          assert_raise ArgumentError, ~r/requires a non-empty #{@id} string/, fn ->
            apply(Events, @fun, [bad_id])
          end
        end
      end
    end
  end
end
