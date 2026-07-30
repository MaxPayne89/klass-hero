defmodule KlassHero.Shared.Adapters.Driven.Events.PubSubBroadcasterTest do
  use ExUnit.Case, async: true

  alias KlassHero.Shared.Adapters.Driven.Events.PubSubBroadcaster
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  describe "broadcast/3" do
    test "returns :ok and delivers tagged message to subscriber" do
      topic = "broadcaster_test:#{:erlang.unique_integer([:positive])}"
      Phoenix.PubSub.subscribe(KlassHero.PubSub, topic)

      event = IntegrationEvent.new(:test_event, :test_context, :test_agg, "agg-1", %{foo: "bar"})

      assert :ok =
               PubSubBroadcaster.broadcast(event, topic,
                 config_key: :event_publisher,
                 message_tag: :domain_event,
                 log_label: "event",
                 extra_metadata: [aggregate_id: event.entity_id]
               )

      assert_receive {:domain_event, received}
      assert received.event_type == :test_event
      assert received.entity_id == "agg-1"
    end

    test "uses the correct message tag in broadcast tuple" do
      topic = "broadcaster_test:#{:erlang.unique_integer([:positive])}"
      Phoenix.PubSub.subscribe(KlassHero.PubSub, topic)

      event = IntegrationEvent.new(:integration_test, :test_ctx, :test_entity, "ent-1", %{})

      assert :ok =
               PubSubBroadcaster.broadcast(event, topic,
                 config_key: :integration_event_publisher,
                 message_tag: :integration_event,
                 log_label: "integration event",
                 extra_metadata: [entity_id: event.entity_id]
               )

      assert_receive {:integration_event, received}
      assert received.event_type == :integration_test
      assert received.entity_id == "ent-1"
    end

    test "extra_metadata defaults to empty list when omitted" do
      topic = "broadcaster_test:#{:erlang.unique_integer([:positive])}"
      Phoenix.PubSub.subscribe(KlassHero.PubSub, topic)

      event = IntegrationEvent.new(:minimal_event, :test_context, :test_agg, "agg-2", %{})

      assert :ok =
               PubSubBroadcaster.broadcast(event, topic,
                 config_key: :event_publisher,
                 message_tag: :domain_event,
                 log_label: "event"
               )

      assert_receive {:domain_event, received}
      assert received.event_type == :minimal_event
    end
  end

  describe "pubsub_server/1" do
    test "returns configured PubSub server" do
      assert PubSubBroadcaster.pubsub_server(:event_publisher) == KlassHero.PubSub
    end

    test "falls back to KlassHero.PubSub when config key is missing" do
      assert PubSubBroadcaster.pubsub_server(:nonexistent_config_key) == KlassHero.PubSub
    end
  end
end
