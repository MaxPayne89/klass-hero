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
     (the `assigned_at`/`unassigned_at` `DateTime`s are never put in it), so it
     round-trips through `EventSerializer` losslessly.
  """
  use ExUnit.Case, async: true

  alias KlassHero.Messaging.Adapters.Driving.Events.StaffAssignmentHandler
  alias KlassHero.Provider.Domain.Events.ProviderEvents
  alias KlassHero.Provider.ProgramStaffAssignment
  alias KlassHero.Provider.StaffMember
  alias KlassHero.Shared.Adapters.Driven.Events.EventConsumerRegistry
  alias KlassHero.Shared.Adapters.Driven.Events.EventSerializer
  alias KlassHero.Shared.Domain.Events.Event

  @assignment %ProgramStaffAssignment{
    provider_id: "prov-1",
    program_id: "prog-1",
    staff_member_id: "staff-1",
    assigned_at: ~U[2026-01-01 12:00:00Z],
    unassigned_at: ~U[2026-01-02 12:00:00Z]
  }
  @staff_member %StaffMember{user_id: "user-1"}

  describe "durable-delivery wiring: factory → topic → registry" do
    test "staff_assigned_to_program resolves to the Messaging handler" do
      event = ProviderEvents.staff_assigned_to_program(@assignment, @staff_member)

      assert Event.topic(event) ==
               "integration:provider:staff_assigned_to_program"

      assert {StaffAssignmentHandler, :handle_event} in EventConsumerRegistry.consumers_for(
               "integration:provider:staff_assigned_to_program"
             )
    end

    test "staff_unassigned_from_program resolves to the Messaging handler" do
      event = ProviderEvents.staff_unassigned_from_program(@assignment, @staff_member)

      assert Event.topic(event) ==
               "integration:provider:staff_unassigned_from_program"

      assert {StaffAssignmentHandler, :handle_event} in EventConsumerRegistry.consumers_for(
               "integration:provider:staff_unassigned_from_program"
             )
    end
  end

  describe "serialization safety: no DateTime in the integration payload" do
    test "staff_assigned_to_program payload round-trips losslessly through the serializer" do
      event = ProviderEvents.staff_assigned_to_program(@assignment, @staff_member)

      round_tripped =
        event
        |> EventSerializer.serialize()
        |> jsonify()
        |> EventSerializer.deserialize()

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
      event = ProviderEvents.staff_unassigned_from_program(@assignment, @staff_member)

      round_tripped =
        event
        |> EventSerializer.serialize()
        |> jsonify()
        |> EventSerializer.deserialize()

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
