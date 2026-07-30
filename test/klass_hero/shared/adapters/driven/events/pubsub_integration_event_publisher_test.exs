defmodule KlassHero.Shared.Adapters.Driven.Events.PubSubIntegrationEventPublisherTest do
  use KlassHero.DataCase, async: false
  use Oban.Testing, repo: KlassHero.Repo

  alias KlassHero.Shared.Adapters.Driven.Events.PubSubIntegrationEventPublisher
  alias KlassHero.Shared.Adapters.Driven.Workers.EventDeliveryWorker
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  # This publisher used to double as the durability path: publishing a critical event
  # also enqueued one Oban job per registered handler. The outbox does that now, from
  # inside the producer's transaction, so publishing broadcasts and nothing more.
  describe "publish/1" do
    test "broadcasts on the event's derived topic and enqueues nothing" do
      event = IntegrationEvent.new(:test_event, :test_context, :test_entity, "entity-1", %{user_id: 1})
      topic = PubSubIntegrationEventPublisher.derive_topic(event)
      :ok = Phoenix.PubSub.subscribe(KlassHero.PubSub, topic)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = PubSubIntegrationEventPublisher.publish(event)

        assert_receive {:integration_event, %IntegrationEvent{event_type: :test_event}}
        refute_enqueued(worker: EventDeliveryWorker)
      end)
    end

    test "a critical event is no more durable here than a normal one" do
      event =
        IntegrationEvent.new(:test_critical, :test_context, :test_entity, "entity-2", %{user_id: 1},
          criticality: :critical
        )

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = PubSubIntegrationEventPublisher.publish(event)
        refute_enqueued(worker: EventDeliveryWorker)
      end)
    end
  end

  describe "publish/2 with explicit topic" do
    test "returns :ok when publishing to an explicit topic" do
      event =
        IntegrationEvent.new(
          :some_event,
          :test_context,
          :test_entity,
          "entity-1",
          %{}
        )

      topic = "integration:test_context:some_event"

      assert :ok = PubSubIntegrationEventPublisher.publish(event, topic)
    end

    test "delivers message to subscriber on the explicit topic" do
      event =
        IntegrationEvent.new(
          :some_event,
          :test_context,
          :test_entity,
          "entity-2",
          %{key: "value"}
        )

      topic = "integration:test_context:some_event_#{:erlang.unique_integer([:positive])}"

      Phoenix.PubSub.subscribe(KlassHero.PubSub, topic)
      assert :ok = PubSubIntegrationEventPublisher.publish(event, topic)

      assert_receive {:integration_event, received_event}
      assert received_event.event_type == :some_event
      assert received_event.entity_id == "entity-2"
    end
  end

  describe "publish_all/1" do
    test "returns :ok when all events publish successfully" do
      events = [
        IntegrationEvent.new(:event_a, :ctx_a, :entity, "e-1", %{}),
        IntegrationEvent.new(:event_b, :ctx_b, :entity, "e-2", %{})
      ]

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = PubSubIntegrationEventPublisher.publish_all(events)
        refute_enqueued(worker: EventDeliveryWorker)
      end)
    end
  end

  describe "build_topic/2" do
    test "formats topic as integration:{context}:{event_type}" do
      assert PubSubIntegrationEventPublisher.build_topic(:identity, :child_data_anonymized) ==
               "integration:identity:child_data_anonymized"
    end

    test "works with any atom context and event type" do
      assert PubSubIntegrationEventPublisher.build_topic(:enrollment, :invite_claimed) ==
               "integration:enrollment:invite_claimed"
    end
  end

  describe "derive_topic/1" do
    test "derives topic from an IntegrationEvent struct" do
      event =
        IntegrationEvent.new(:child_data_anonymized, :identity, :child, "child-uuid", %{})

      assert PubSubIntegrationEventPublisher.derive_topic(event) ==
               "integration:identity:child_data_anonymized"
    end
  end

  # Temporarily overrides :critical_event_handlers config for the duration of `fun`,
  # restoring the original value on exit regardless of success or failure.
end
