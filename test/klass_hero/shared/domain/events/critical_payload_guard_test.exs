defmodule KlassHero.Shared.Domain.Events.CriticalPayloadGuardTest do
  @moduledoc """
  Guards what a `:critical` event payload may carry across jsonb (#1010, #1311).
  The guard lives in `EventMetadata.validate_critical_payload!/2`, invoked from
  `Event.new/6`.

  Two rules, and the difference between them is the whole point: a value the
  serializer can restore is allowed, a value that would silently arrive as
  something else is not.
  """
  use ExUnit.Case, async: true

  alias KlassHero.Shared.Domain.Events.Event

  # Type is lost across jsonb with nothing recording what it was, so the consumer
  # receives a string it did not ask for. Each case pins the path in the message —
  # the point of the guard is saying *where*.
  @rejected [
    {"a bare atom", %{status: :pending}, "status"},
    {"a tuple", %{coord: {1, 2}}, "coord"},
    {"an atom nested in a map", %{outer: %{inner: :atom_value}}, "outer.inner"},
    {"an atom nested in a list", %{items: ["ok", :nope]}, "items.1"},
    {"a schema struct", %{ref: %URI{host: "example.com"}}, "ref"}
  ]

  # CriticalEventSerializer records these on the way out and rebuilds them on the
  # way in (#1311), so the consumer gets what the producer sent.
  @restorable [
    {"a Date", %{on: ~D[2026-08-12]}},
    {"a Time", %{at: ~T[15:00:00]}},
    {"a DateTime", %{happened_at: ~U[2026-08-12 10:00:00Z]}},
    {"a NaiveDateTime", %{naive: ~N[2026-08-12 10:00:00]}},
    {"a Decimal", %{price: Decimal.new("12.50")}}
  ]

  describe "critical payloads reject values that lose their type" do
    for {label, payload, path} <- @rejected do
      test "rejects #{label}" do
        error =
          assert_raise ArgumentError, fn ->
            critical(unquote(Macro.escape(payload)))
          end

        assert error.message =~ "cannot survive jsonb serialization",
               "expected the guard's message, got: #{error.message}"

        assert error.message =~ unquote(path),
               "expected the message to name the path #{unquote(path)}, got: #{error.message}"
      end
    end
  end

  describe "critical payloads accept what the serializer can restore" do
    for {label, payload} <- @restorable do
      test "accepts #{label}" do
        payload = unquote(Macro.escape(payload))

        assert critical(payload).payload == payload
      end
    end

    test "accepts a restorable value nested in a map and a list" do
      payload = %{outer: %{on: ~D[2026-08-12]}, items: ["ok", Decimal.new("1.00")]}

      assert critical(payload).payload == payload
    end
  end

  describe "critical payloads accept JSON scalars and containers" do
    test "allows strings, numbers, booleans, and nil" do
      event = critical(%{name: "Alice", age: 7, ratio: 1.5, active: true, deleted: nil})

      assert event.payload.name == "Alice"
      assert event.payload.active == true
      assert event.payload.deleted == nil
    end

    test "allows scalars nested in maps and lists" do
      payload = %{address: %{city: "Berlin"}, tags: ["a", "b"], items: [%{n: 1}, %{n: 2}]}

      assert critical(payload).payload == payload
    end

    test "allows an empty payload" do
      assert %Event{} = critical(%{})
    end
  end

  # The exemption is stale — ADR-0014 made every event serialize — but ungating it
  # raises on the atoms `:normal` payloads carry throughout, so it stands until those
  # are encoded. See `EventMetadata`'s moduledoc.
  describe "non-critical events are exempt" do
    test "allows an atom payload value on a :normal event" do
      event = normal(%{status: :pending})

      assert event.payload.status == :pending
    end

    test "defaults to :normal (exempt) when criticality is unset" do
      event = Event.new(:test_event, :test_context, :test, "agg-1", %{status: :pending})

      assert event.payload.status == :pending
    end
  end

  defp critical(payload), do: build(payload, criticality: :critical)
  defp normal(payload), do: build(payload, criticality: :normal)

  defp build(payload, opts) do
    Event.new(:test_event, :test_context, :test, "agg-1", payload, opts)
  end
end
