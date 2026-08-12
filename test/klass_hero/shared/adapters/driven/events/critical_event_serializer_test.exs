defmodule KlassHero.Shared.Adapters.Driven.Events.CriticalEventSerializerTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias KlassHero.Shared.Adapters.Driven.Events.CriticalEventSerializer
  alias KlassHero.Shared.Domain.Events.Event

  # Payload keys must survive String.to_existing_atom/1, so the generator draws from
  # atoms this module has already created. The space is deliberately wider than
  # @max_keys: map_of/3 needs unique keys, and asking for as many as exist starves it
  # into StreamData.TooManyDuplicatesError.
  @keys [:alpha, :beta, :gamma, :delta, :epsilon, :zeta, :eta, :theta]
  @max_keys 3

  describe "round-trip" do
    test "serialize then deserialize produces equivalent struct" do
      event =
        Event.new(
          :child_data_anonymized,
          :family,
          :child,
          "child-uuid",
          %{child_id: "child-uuid", reason: "gdpr_request"},
          criticality: :critical,
          version: 2
        )

      serialized = CriticalEventSerializer.serialize(event)
      deserialized = CriticalEventSerializer.deserialize(serialized)

      assert deserialized.event_id == event.event_id
      assert deserialized.event_type == :child_data_anonymized
      assert deserialized.source_context == :family
      assert deserialized.entity_type == :child
      assert deserialized.entity_id == "child-uuid"
      assert deserialized.payload == %{child_id: "child-uuid", reason: "gdpr_request"}
      assert deserialized.metadata.criticality == :critical
      assert deserialized.version == 2
    end

    test "serialized form includes version and source_context" do
      event =
        Event.new(:test, :enrollment, :invite, "id", %{}, version: 3)

      serialized = CriticalEventSerializer.serialize(event)

      assert serialized["source_context"] == "enrollment"
      assert serialized["version"] == 3
    end
  end

  describe "payload key atomization" do
    test "restores atom keys after JSON round-trip" do
      event = Event.new(:test, :test_context, :test, "id", %{user_id: 1, name: "Alice"})
      serialized = CriticalEventSerializer.serialize(event)

      # Simulate JSON round-trip (keys become strings)
      json_cycled = Jason.decode!(Jason.encode!(serialized))

      deserialized = CriticalEventSerializer.deserialize(json_cycled)

      assert deserialized.payload == %{user_id: 1, name: "Alice"}
    end

    test "handles nested payload maps" do
      event = Event.new(:test, :test_context, :test, "id", %{address: %{city: "Berlin", zip: "10115"}})
      serialized = CriticalEventSerializer.serialize(event)
      json_cycled = Jason.decode!(Jason.encode!(serialized))
      deserialized = CriticalEventSerializer.deserialize(json_cycled)

      assert deserialized.payload == %{address: %{city: "Berlin", zip: "10115"}}
    end

    test "atomizes keys inside maps nested in lists" do
      event = Event.new(:test, :test_context, :test, "id", %{items: [%{name: "Alice"}, %{name: "Bob"}]})
      serialized = CriticalEventSerializer.serialize(event)
      json_cycled = Jason.decode!(Jason.encode!(serialized))
      deserialized = CriticalEventSerializer.deserialize(json_cycled)

      assert deserialized.payload == %{items: [%{name: "Alice"}, %{name: "Bob"}]}
    end
  end

  describe "typed payload values" do
    # The invariant the sidecar exists for. #1311 was one instance of it failing;
    # this covers the whole space rather than the fields that happened to break.
    property "any payload survives the jsonb round-trip unchanged" do
      check all(payload <- payload_generator()) do
        assert round_trip(payload) == payload
      end
    end

    for {label, payload} <- [
          {"a Date", %{alpha: ~D[2026-08-12]}},
          {"a Time", %{alpha: ~T[15:00:00]}},
          {"a DateTime", %{alpha: ~U[2026-08-12 10:00:00Z]}},
          {"a DateTime with microseconds", %{alpha: ~U[2026-08-12 10:00:00.123456Z]}},
          {"a NaiveDateTime", %{alpha: ~N[2026-08-12 10:00:00]}},
          {"a Decimal", %{alpha: Decimal.new("12.50")}},
          {"an atom", %{alpha: :direct}},
          {"an atom nested in a map", %{alpha: %{beta: :program_broadcast}}},
          {"an atom nested in a list", %{alpha: ["x", :text]}},
          {"a typed value nested in a map", %{alpha: %{beta: ~D[2026-08-12]}}},
          {"a typed value nested in a list", %{alpha: ["x", ~T[09:00:00]]}},
          {"typed values beside scalars and nils", %{alpha: ~D[2026-08-12], beta: "x", gamma: nil}},
          # nil and the booleans are atoms too. Tagging them would turn JSON null into
          # the string "nil" and change what every `Map.get(payload, :k) || default`
          # in a consumer returns.
          {"an atom beside nil and booleans", %{alpha: :pending, beta: nil, gamma: true, delta: false}}
        ] do
      test "restores #{label}" do
        payload = unquote(Macro.escape(payload))

        assert round_trip(payload) == payload
      end
    end

    test "keeps the payload plain JSON and puts the types beside it" do
      serialized = serialize(%{alpha: ~D[2026-08-12], beta: "Chess"})

      assert serialized["payload"] == %{"alpha" => "2026-08-12", "beta" => "Chess"}
      assert serialized["payload_types"] == %{"alpha" => "date"}
    end

    test "records no types for an all-scalar payload" do
      assert serialize(%{alpha: "x", beta: %{gamma: 1}, delta: ["a"]})["payload_types"] == %{}
    end

    # Args staged before the sidecar existed. Values stay strings, which is the
    # pre-#1311 behaviour — the in-flight jobs at deploy need exactly that.
    test "leaves values alone when payload_types is absent" do
      legacy = serialize(%{alpha: ~D[2026-08-12]}) |> Map.delete("payload_types")

      assert CriticalEventSerializer.deserialize(legacy).payload == %{alpha: "2026-08-12"}
    end

    test "raises on a struct it cannot restore" do
      event = %Event{
        event_id: "id",
        event_type: :test,
        source_context: :test_context,
        entity_type: :test,
        entity_id: "id",
        occurred_at: DateTime.utc_now(),
        payload: %{alpha: %URI{host: "example.com"}}
      }

      assert_raise ArgumentError, ~r/cannot cross the Oban jsonb boundary/, fn ->
        CriticalEventSerializer.serialize(event)
      end
    end
  end

  describe "metadata round-trip" do
    test "restores metadata atom keys after JSON round-trip" do
      event =
        Event.new(:test, :test_context, :test, "id", %{},
          criticality: :critical,
          correlation_id: "corr-1",
          causation_id: "cause-1"
        )

      serialized = CriticalEventSerializer.serialize(event)
      json_cycled = Jason.decode!(Jason.encode!(serialized))
      deserialized = CriticalEventSerializer.deserialize(json_cycled)

      assert deserialized.metadata.criticality == :critical
      assert deserialized.metadata.correlation_id == "corr-1"
      assert deserialized.metadata.causation_id == "cause-1"
    end

    test "preserves string keys for trace context fields after round-trip" do
      event =
        Event.new(:test_event, :enrollment, :invite, "id-1", %{}, criticality: :normal)

      event_with_trace =
        %{
          event
          | metadata:
              Map.merge(event.metadata, %{
                "traceparent" => "00-abc123-def456-01",
                "tracestate" => ""
              })
        }

      serialized = CriticalEventSerializer.serialize(event_with_trace)
      json_cycled = Jason.decode!(Jason.encode!(serialized))
      deserialized = CriticalEventSerializer.deserialize(json_cycled)

      assert Map.fetch(deserialized.metadata, "traceparent") == {:ok, "00-abc123-def456-01"}
      assert Map.fetch(deserialized.metadata, "tracestate") == {:ok, ""}
      refute Map.has_key?(deserialized.metadata, :traceparent)
      refute Map.has_key?(deserialized.metadata, :tracestate)
    end
  end

  # Jason.encode!/decode! is not ceremony: without it the test compares two in-memory
  # maps and never crosses the boundary that loses the type.
  defp round_trip(payload) do
    payload
    |> serialize()
    |> Jason.encode!()
    |> Jason.decode!()
    |> CriticalEventSerializer.deserialize()
    |> Map.fetch!(:payload)
  end

  defp serialize(payload) do
    :test
    |> Event.new(:test_context, :test, "id", payload)
    |> CriticalEventSerializer.serialize()
  end

  defp payload_generator do
    StreamData.map_of(member_of(@keys), nested_value(), max_length: @max_keys)
  end

  defp nested_value do
    StreamData.tree(leaf_value(), fn child ->
      one_of([
        StreamData.list_of(child, max_length: 3),
        StreamData.map_of(member_of(@keys), child, max_length: @max_keys)
      ])
    end)
  end

  defp leaf_value do
    one_of([
      string(:printable),
      integer(),
      boolean(),
      constant(nil),
      # Drawn from @keys so String.to_existing_atom/1 can restore them, same bet the
      # payload keys already make.
      member_of(@keys),
      map(integer(0..36_500), &Date.add(~D[1990-01-01], &1)),
      map(integer(0..86_399), &Time.add(~T[00:00:00], &1)),
      map(integer(0..2_000_000_000), &DateTime.from_unix!/1),
      map(integer(0..2_000_000_000), &(&1 |> DateTime.from_unix!() |> DateTime.to_naive())),
      map(integer(-1_000_000..1_000_000), &Decimal.new/1)
    ])
  end
end
