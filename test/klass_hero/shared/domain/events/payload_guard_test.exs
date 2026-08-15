defmodule KlassHero.Shared.Domain.Events.PayloadGuardTest do
  @moduledoc """
  Guards what an event payload may carry across jsonb (#1010, #1311, #1317).
  The guard lives in `PayloadGuard.validate_payload!/1`, invoked from `Event.new/5`.

  One rule, and the difference it draws is the whole point: a value `PayloadCodec`
  can restore is allowed, a value that would silently arrive as something else is
  not. The codec is what decides; this asserts the guard asks it, and says *where*
  when the answer is no.
  """
  use ExUnit.Case, async: true

  alias KlassHero.Shared.Domain.Events.Event

  # Nothing records what these were, so a consumer would receive something else.
  # Each case pins the path in the message — the point of the guard is saying where.
  @rejected [
    {"a tuple", %{coord: {1, 2}}, "coord"},
    {"a schema struct", %{ref: %URI{host: "example.com"}}, "ref"},
    {"a tuple nested in a map", %{outer: %{inner: {:a, :b}}}, "outer.inner"},
    {"a struct nested in a list", %{items: ["ok", %URI{host: "x"}]}, "items.1"}
  ]

  # EventSerializer records these on the way out and rebuilds them on the
  # way in, so the consumer gets what the producer sent.
  @restorable [
    {"an atom", %{status: :pending}},
    {"a Date", %{on: ~D[2026-08-12]}},
    {"a Time", %{at: ~T[15:00:00]}},
    {"a DateTime", %{happened_at: ~U[2026-08-12 10:00:00Z]}},
    {"a NaiveDateTime", %{naive: ~N[2026-08-12 10:00:00]}},
    {"a Decimal", %{price: Decimal.new("12.50")}}
  ]

  describe "payloads reject values that lose their type" do
    for {label, payload, path} <- @rejected do
      test "rejects #{label}" do
        error =
          assert_raise ArgumentError, fn ->
            build(unquote(Macro.escape(payload)))
          end

        assert error.message =~ "cannot survive jsonb serialization",
               "expected the guard's message, got: #{error.message}"

        assert error.message =~ unquote(path),
               "expected the message to name the path #{unquote(path)}, got: #{error.message}"
      end
    end
  end

  describe "payloads accept what the serializer can restore" do
    for {label, payload} <- @restorable do
      test "accepts #{label}" do
        payload = unquote(Macro.escape(payload))

        assert build(payload).payload == payload
      end
    end

    test "accepts a restorable value nested in a map and a list" do
      payload = %{outer: %{on: ~D[2026-08-12]}, items: ["ok", Decimal.new("1.00")]}

      assert build(payload).payload == payload
    end
  end

  describe "payloads accept JSON scalars and containers" do
    test "allows strings, numbers, booleans, and nil" do
      event = build(%{name: "Alice", age: 7, ratio: 1.5, active: true, deleted: nil})

      assert event.payload.name == "Alice"
      assert event.payload.active == true
      assert event.payload.deleted == nil
    end

    test "allows scalars nested in maps and lists" do
      payload = %{address: %{city: "Berlin"}, tags: ["a", "b"], items: [%{n: 1}, %{n: 2}]}

      assert build(payload).payload == payload
    end

    test "allows an empty payload" do
      assert %Event{} = build(%{})
    end
  end

  # The guard used to run for events marked critical only, on the reasoning that an
  # unmarked one was never serialized. ADR-0014 ended that — every staged event takes
  # the same Outbox → Oban → EventDeliveryWorker path — and both of #1311's production
  # bugs sat in the gap it left. #1326 then removed the marker itself, so there is one
  # kind of event and one rule for it.
  describe "the guard is ungated" do
    test "rejects an unencodable value on any event" do
      assert_raise ArgumentError, ~r/cannot survive jsonb serialization/, fn ->
        Event.new(:test_event, :test_context, :test, "agg-1", %{coord: {1, 2}})
      end
    end
  end

  defp build(payload) do
    Event.new(:test_event, :test_context, :test, "agg-1", payload)
  end
end
