defmodule KlassHero.Enrollment.Domain.Events.EnrollmentIntegrationEventsTest do
  @moduledoc "Tests for the EnrollmentIntegrationEvents factory module."

  use ExUnit.Case, async: true

  alias KlassHero.Enrollment.Domain.Events.EnrollmentIntegrationEvents, as: Events
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  # Every enrollment integration-event factory shares one contract: build an event
  # with stable identity fields, let the base payload's id win over any
  # caller-supplied id (preserving extras), and raise on a blank id. The table
  # drives that shape; enrollment_created's parent_user_id passthrough is the one
  # factory-specific assertion, kept below the table.
  @factories [
    %{fun: :invite_claimed, id: :invite_id, entity: :invite},
    %{fun: :enrollment_cancelled, id: :enrollment_id, entity: :enrollment},
    %{fun: :participant_policy_set, id: :program_id, entity: :participant_policy},
    %{fun: :enrollment_created, id: :enrollment_id, entity: :enrollment}
  ]

  for %{fun: fun, id: id, entity: entity} <- @factories do
    describe "#{fun}/3" do
      @fun fun
      @id id
      @entity entity

      test "builds an event with stable identity fields" do
        event = apply(Events, @fun, ["id-1"])

        assert %IntegrationEvent{} = event
        assert event.event_type == @fun
        assert event.source_context == :enrollment
        assert event.entity_type == @entity
        assert event.entity_id == "id-1"
      end

      test "base payload id wins over caller-supplied and preserves extras" do
        payload = %{@id => "overridden", :extra => "data"}
        event = apply(Events, @fun, ["real-id", payload])

        assert Map.get(event.payload, @id) == "real-id"
        assert event.payload.extra == "data"
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

  describe "enrollment_created/3 payload" do
    test "carries parent_user_id through to the integration event" do
      event =
        Events.enrollment_created("enr-1", %{
          child_id: "child-1",
          parent_id: "parent-1",
          parent_user_id: "puser-1",
          program_id: "prog-1",
          status: :pending
        })

      assert event.payload.parent_user_id == "puser-1"
    end
  end
end
