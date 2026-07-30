defmodule KlassHero.Shared.Adapters.Driven.Events.CriticalEventSerializerTest do
  use ExUnit.Case, async: true

  alias KlassHero.Shared.Adapters.Driven.Events.CriticalEventSerializer
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  describe "round-trip" do
    test "serialize then deserialize produces equivalent struct" do
      event =
        IntegrationEvent.new(
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
        IntegrationEvent.new(:test, :enrollment, :invite, "id", %{}, version: 3)

      serialized = CriticalEventSerializer.serialize(event)

      assert serialized["source_context"] == "enrollment"
      assert serialized["version"] == 3
    end
  end

  describe "payload key atomization" do
    test "restores atom keys after JSON round-trip" do
      event = IntegrationEvent.new(:test, :test_context, :test, "id", %{user_id: 1, name: "Alice"})
      serialized = CriticalEventSerializer.serialize(event)

      # Simulate JSON round-trip (keys become strings)
      json_cycled = Jason.decode!(Jason.encode!(serialized))

      deserialized = CriticalEventSerializer.deserialize(json_cycled)

      assert deserialized.payload == %{user_id: 1, name: "Alice"}
    end

    test "handles nested payload maps" do
      event = IntegrationEvent.new(:test, :test_context, :test, "id", %{address: %{city: "Berlin", zip: "10115"}})
      serialized = CriticalEventSerializer.serialize(event)
      json_cycled = Jason.decode!(Jason.encode!(serialized))
      deserialized = CriticalEventSerializer.deserialize(json_cycled)

      assert deserialized.payload == %{address: %{city: "Berlin", zip: "10115"}}
    end

    test "atomizes keys inside maps nested in lists" do
      event = IntegrationEvent.new(:test, :test_context, :test, "id", %{items: [%{name: "Alice"}, %{name: "Bob"}]})
      serialized = CriticalEventSerializer.serialize(event)
      json_cycled = Jason.decode!(Jason.encode!(serialized))
      deserialized = CriticalEventSerializer.deserialize(json_cycled)

      assert deserialized.payload == %{items: [%{name: "Alice"}, %{name: "Bob"}]}
    end
  end

  describe "metadata round-trip" do
    test "restores metadata atom keys after JSON round-trip" do
      event =
        IntegrationEvent.new(:test, :test_context, :test, "id", %{},
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
        IntegrationEvent.new(:test_event, :enrollment, :invite, "id-1", %{}, criticality: :normal)

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
end
