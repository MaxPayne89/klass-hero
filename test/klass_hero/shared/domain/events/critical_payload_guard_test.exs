defmodule KlassHero.Shared.Domain.Events.CriticalPayloadGuardTest do
  @moduledoc """
  Guards that `:critical` event payloads carry only JSON scalars so they
  survive jsonb serialization intact (see #1010). The guard lives in
  `EventMetadata.validate_critical_payload!/2` and is invoked from both
  `DomainEvent.new/5` and `Event.new/6`.
  """
  use ExUnit.Case, async: true

  alias KlassHero.Shared.Domain.Events.Event

  defp new_domain(payload, opts \\ [criticality: :critical]) do
    Event.new(:test_event, :test_context, :test, "agg-1", payload, opts)
  end

  defp new_integration(payload, opts \\ [criticality: :critical]) do
    Event.new(:test_event, :test_ctx, :test, "id-1", payload, opts)
  end

  describe "critical events reject non-scalar payload values" do
    test "raises on a DateTime payload value" do
      assert_raise ArgumentError, ~r/not a JSON scalar/, fn ->
        new_domain(%{happened_at: DateTime.utc_now()})
      end
    end

    test "raises on a bare atom payload value" do
      assert_raise ArgumentError, ~r/not a JSON scalar/, fn ->
        new_domain(%{status: :pending})
      end
    end

    test "raises on a tuple payload value" do
      assert_raise ArgumentError, ~r/not a JSON scalar/, fn ->
        new_domain(%{coord: {1, 2}})
      end
    end

    test "raises on a non-scalar nested inside a map" do
      assert_raise ArgumentError, ~r/not a JSON scalar/, fn ->
        new_domain(%{outer: %{inner: :atom_value}})
      end
    end

    test "raises on a non-scalar nested inside a list" do
      assert_raise ArgumentError, ~r/not a JSON scalar/, fn ->
        new_domain(%{items: ["ok", DateTime.utc_now()]})
      end
    end

    test "error message names the offending path" do
      error =
        assert_raise ArgumentError, fn ->
          new_domain(%{outer: %{when: DateTime.utc_now()}})
        end

      assert error.message =~ "outer.when"
    end

    test "applies to Event too" do
      assert_raise ArgumentError, ~r/not a JSON scalar/, fn ->
        new_integration(%{happened_at: DateTime.utc_now()})
      end
    end
  end

  describe "critical events accept JSON scalars and containers" do
    test "allows strings, numbers, booleans, and nil" do
      event = new_domain(%{name: "Alice", age: 7, ratio: 1.5, active: true, deleted: nil})
      assert event.payload.name == "Alice"
      assert event.payload.active == true
      assert event.payload.deleted == nil
    end

    test "allows scalars nested in maps and lists" do
      payload = %{address: %{city: "Berlin"}, tags: ["a", "b"], items: [%{n: 1}, %{n: 2}]}
      event = new_domain(payload)
      assert event.payload == payload
    end

    test "allows an empty payload" do
      assert %Event{} = new_domain(%{})
    end
  end

  describe "non-critical events are exempt" do
    test "allows a DateTime payload value on a :normal event" do
      event = new_domain(%{happened_at: ~U[2026-07-06 12:00:00Z]}, criticality: :normal)
      assert %DateTime{} = event.payload.happened_at
    end

    test "defaults to :normal (exempt) when criticality is unset" do
      event = Event.new(:test_event, :test_context, :test, "agg-1", %{status: :pending})
      assert event.payload.status == :pending
    end
  end
end
