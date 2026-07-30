defmodule KlassHero.Provider.StaffAssignmentDurabilityTest do
  @moduledoc """
  Regression coverage for #1004: the `staff_assigned_to_program` /
  `staff_unassigned_from_program` integration events must reach Messaging's handler,
  and their payload must survive the Oban `serialize → jsonb → deserialize` round
  trip.

  These are the two pieces the fix adds:

  1. **Wiring** — both topics resolve to Messaging's `StaffAssignmentHandler` via
     the real `:event_consumers` config. Durability is no longer conditional on an
     event being marked critical: being in that table is the whole condition.

  2. **Serialization safety** — the payload carries only string/UUID fields
     (the `assigned_at`/`unassigned_at` `DateTime`s are trimmed at the promotion
     boundary), so it round-trips through `CriticalEventSerializer` losslessly.
  """
  use ExUnit.Case, async: true

  alias KlassHero.Messaging.Adapters.Driving.Events.StaffAssignmentHandler
  alias KlassHero.Provider.Domain.Events.ProviderIntegrationEvents
  alias KlassHero.Shared.Adapters.Driven.Events.CriticalEventSerializer
  alias KlassHero.Shared.Adapters.Driven.Events.EventConsumerRegistry
  alias KlassHero.Shared.Adapters.Driven.Events.PubSubIntegrationEventPublisher

  @assigned_payload %{
    provider_id: "prov-1",
    program_id: "prog-1",
    staff_user_id: "user-1"
  }

  describe "durable-delivery wiring: factory → topic → registry" do
    test "staff_assigned_to_program resolves to the Messaging handler" do
      event = ProviderIntegrationEvents.staff_assigned_to_program("staff-1", @assigned_payload)

      assert PubSubIntegrationEventPublisher.derive_topic(event) ==
               "integration:provider:staff_assigned_to_program"

      assert {StaffAssignmentHandler, :handle_event} in EventConsumerRegistry.consumers_for(
               "integration:provider:staff_assigned_to_program"
             )
    end

    test "staff_unassigned_from_program resolves to the Messaging handler" do
      event = ProviderIntegrationEvents.staff_unassigned_from_program("staff-1", @assigned_payload)

      assert PubSubIntegrationEventPublisher.derive_topic(event) ==
               "integration:provider:staff_unassigned_from_program"

      assert {StaffAssignmentHandler, :handle_event} in EventConsumerRegistry.consumers_for(
               "integration:provider:staff_unassigned_from_program"
             )
    end
  end

  describe "serialization safety: no DateTime in the integration payload" do
    test "staff_assigned_to_program payload round-trips losslessly through the serializer" do
      event = ProviderIntegrationEvents.staff_assigned_to_program("staff-1", @assigned_payload)

      round_tripped =
        event
        |> CriticalEventSerializer.serialize()
        |> jsonify()
        |> CriticalEventSerializer.deserialize()

      # Trimmed at the promotion boundary — no DateTime crosses the boundary.
      refute Map.has_key?(round_tripped.payload, :assigned_at)

      assert round_tripped.payload == %{
               staff_member_id: "staff-1",
               provider_id: "prov-1",
               program_id: "prog-1",
               staff_user_id: "user-1"
             }
    end

    test "staff_unassigned_from_program payload round-trips losslessly through the serializer" do
      event = ProviderIntegrationEvents.staff_unassigned_from_program("staff-1", @assigned_payload)

      round_tripped =
        event
        |> CriticalEventSerializer.serialize()
        |> jsonify()
        |> CriticalEventSerializer.deserialize()

      refute Map.has_key?(round_tripped.payload, :unassigned_at)

      assert round_tripped.payload == %{
               staff_member_id: "staff-1",
               provider_id: "prov-1",
               program_id: "prog-1",
               staff_user_id: "user-1"
             }
    end
  end

  # Mirror the real Oban path: serialized args are stored as jsonb (string keys,
  # JSON-encodable values only) before the worker deserializes them.
  defp jsonify(args), do: args |> Jason.encode!() |> Jason.decode!()
end
