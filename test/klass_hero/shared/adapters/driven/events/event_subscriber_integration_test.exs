defmodule KlassHero.Shared.Adapters.Driven.Events.EventSubscriberIntegrationTest do
  @moduledoc """
  Integration tests for the EventSubscriber → Handler flow.

  Tests the full event dispatch pipeline using real PubSub broadcasting.
  These tests verify that:
  - Events published via PubSub reach subscribed handlers
  - Topic routing works correctly
  - Error handling keeps subscribers alive
  - Multiple subscribers can coexist
  """

  use KlassHero.DataCase, async: false

  import KlassHero.EventTestHelper

  alias Ecto.Adapters.SQL.Sandbox
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Events.EventSubscriber
  alias KlassHero.Shared.Adapters.Driven.Events.PubSubEventPublisher
  alias KlassHero.Shared.Adapters.Driven.Persistence.Schemas.ProcessedEvent
  alias KlassHero.Shared.CriticalEventDispatcher
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.Domain.Events.IntegrationEvent
  alias KlassHero.Test.CriticalFailingTestHandler
  alias KlassHero.Test.CriticalTestHandler

  @pubsub KlassHero.PubSub

  setup do
    # Ensure PubSub is available (started in application.ex)
    assert Process.whereis(@pubsub) != nil, "PubSub server not running"
    :ok
  end

  describe "happy path: publish -> subscribe -> handle" do
    test "handler receives event published to subscribed topic" do
      topic = "test:event_one"

      {:ok, subscriber} =
        start_test_subscriber(
          topics: [topic],
          test_pid: self()
        )

      on_exit(fn -> stop_test_subscriber(subscriber) end)

      # Small delay for subscription to complete
      Process.sleep(10)

      event = DomainEvent.new(:event_one, 1, :test, %{data: "hello"})
      :ok = publish_via_pubsub(event, topic: topic)

      handled_event = assert_event_handled(:event_one)
      assert handled_event.event_id == event.event_id
      assert handled_event.payload.data == "hello"
    end

    test "handler receives events from multiple topics" do
      topics = ["test:event_a", "test:event_b"]

      {:ok, subscriber} =
        start_test_subscriber(
          topics: topics,
          test_pid: self()
        )

      on_exit(fn -> stop_test_subscriber(subscriber) end)
      Process.sleep(10)

      event_a = DomainEvent.new(:event_a, 1, :test, %{type: "a"})
      event_b = DomainEvent.new(:event_b, 2, :test, %{type: "b"})

      :ok = publish_via_pubsub(event_a, topic: "test:event_a")
      :ok = publish_via_pubsub(event_b, topic: "test:event_b")

      assert_event_handled(:event_a)
      assert_event_handled(:event_b)
    end

    test "uses PubSubEventPublisher.derive_topic for automatic topic derivation" do
      {:ok, subscriber} =
        start_test_subscriber(
          topics: ["user:user_registered"],
          test_pid: self()
        )

      on_exit(fn -> stop_test_subscriber(subscriber) end)
      Process.sleep(10)

      event = DomainEvent.new(:user_registered, 123, :user, %{email: "test@example.com"})

      # Verify topic derivation
      topic = PubSubEventPublisher.derive_topic(event)
      assert topic == "user:user_registered"

      # Publish without explicit topic - should derive automatically
      :ok = publish_via_pubsub(event)

      handled_event = assert_event_handled(:user_registered)
      assert handled_event.aggregate_id == 123
    end

    test "event payload is preserved through the pipeline" do
      {:ok, subscriber} =
        start_test_subscriber(
          topics: ["test:payload_check"],
          test_pid: self()
        )

      on_exit(fn -> stop_test_subscriber(subscriber) end)
      Process.sleep(10)

      payload = %{
        name: "Test User",
        email: "test@example.com",
        metadata: %{source: "integration_test"}
      }

      event = DomainEvent.new(:payload_check, 42, :test, payload)
      :ok = publish_via_pubsub(event, topic: "test:payload_check")

      handled_event = assert_event_handled(:payload_check)
      assert handled_event.payload == payload
      assert handled_event.aggregate_id == 42
      assert handled_event.aggregate_type == :test
    end
  end

  describe "topic filtering" do
    test "handler does not receive events from unsubscribed topics" do
      {:ok, subscriber} =
        start_test_subscriber(
          topics: ["test:subscribed"],
          test_pid: self()
        )

      on_exit(fn -> stop_test_subscriber(subscriber) end)
      Process.sleep(10)

      # Publish to a different topic
      event = DomainEvent.new(:unsubscribed_event, 1, :test, %{})
      :ok = publish_via_pubsub(event, topic: "test:unsubscribed")

      refute_event_handled(100)
    end

    test "multiple subscribers can subscribe to the same topic" do
      topic = "shared:event"

      {:ok, subscriber1} =
        start_test_subscriber(
          topics: [topic],
          test_pid: self()
        )

      {:ok, subscriber2} =
        start_test_subscriber(
          topics: [topic],
          test_pid: self()
        )

      on_exit(fn ->
        stop_test_subscriber(subscriber1)
        stop_test_subscriber(subscriber2)
      end)

      Process.sleep(10)

      event = DomainEvent.new(:shared_event, 1, :shared, %{})
      :ok = publish_via_pubsub(event, topic: topic)

      # Both subscribers should receive the event
      assert_event_handled(:shared_event)
      assert_event_handled(:shared_event)
    end

    test "subscriber with multiple topics only receives events for subscribed topics" do
      {:ok, subscriber} =
        start_test_subscriber(
          topics: ["test:first", "test:second"],
          test_pid: self()
        )

      on_exit(fn -> stop_test_subscriber(subscriber) end)
      Process.sleep(10)

      # Publish to subscribed topic
      event1 = DomainEvent.new(:first, 1, :test, %{})
      :ok = publish_via_pubsub(event1, topic: "test:first")
      assert_event_handled(:first)

      # Publish to unsubscribed topic
      event2 = DomainEvent.new(:third, 2, :test, %{})
      :ok = publish_via_pubsub(event2, topic: "test:third")
      refute_event_handled(100)

      # Publish to second subscribed topic
      event3 = DomainEvent.new(:second, 3, :test, %{})
      :ok = publish_via_pubsub(event3, topic: "test:second")
      assert_event_handled(:second)
    end
  end

  describe "error handling" do
    test "subscriber continues after handler returns {:error, reason}" do
      topic = "test:error_handling"

      {:ok, subscriber} =
        start_test_subscriber(
          topics: [topic],
          test_pid: self(),
          behavior: {:error, :simulated_error}
        )

      on_exit(fn -> stop_test_subscriber(subscriber) end)
      Process.sleep(10)

      event1 = DomainEvent.new(:first_event, 1, :test, %{})
      event2 = DomainEvent.new(:second_event, 2, :test, %{})

      :ok = publish_via_pubsub(event1, topic: topic)
      :ok = publish_via_pubsub(event2, topic: topic)

      # Both events should be handled (subscriber doesn't crash)
      assert_event_handled(:first_event)
      assert_event_handled(:second_event)

      # Subscriber should still be alive
      assert Process.alive?(subscriber)
    end

    test "subscriber continues after handler crashes" do
      topic = "test:crash_handling"

      {:ok, subscriber} =
        start_test_subscriber(
          topics: [topic],
          test_pid: self(),
          behavior: :crash
        )

      on_exit(fn -> stop_test_subscriber(subscriber) end)
      Process.sleep(10)

      event1 = DomainEvent.new(:crash_event, 1, :test, %{})
      event2 = DomainEvent.new(:after_crash, 2, :test, %{})

      # Capture log to avoid test noise
      ExUnit.CaptureLog.capture_log(fn ->
        :ok = publish_via_pubsub(event1, topic: topic)
        # First event triggers notification before crash
        assert_event_handled(:crash_event)
        Process.sleep(50)
      end)

      # Subscriber should still be alive (crash was rescued)
      assert Process.alive?(subscriber)

      # Should still be able to handle more events
      ExUnit.CaptureLog.capture_log(fn ->
        :ok = publish_via_pubsub(event2, topic: topic)
        assert_event_handled(:after_crash)
      end)
    end

    test "subscriber handles :ignore return value" do
      topic = "test:ignore_handling"

      {:ok, subscriber} =
        start_test_subscriber(
          topics: [topic],
          test_pid: self(),
          behavior: :ignore
        )

      on_exit(fn -> stop_test_subscriber(subscriber) end)
      Process.sleep(10)

      event = DomainEvent.new(:ignored_event, 1, :test, %{})
      :ok = publish_via_pubsub(event, topic: topic)

      # Event was received (handler notifies test process before returning :ignore)
      assert_event_handled(:ignored_event)

      # Subscriber still alive
      assert Process.alive?(subscriber)
    end
  end

  describe "subscriber lifecycle" do
    test "subscriber can be stopped gracefully" do
      {:ok, subscriber} =
        start_test_subscriber(
          topics: ["test:lifecycle"],
          test_pid: self()
        )

      assert Process.alive?(subscriber)

      :ok = stop_test_subscriber(subscriber)

      Process.sleep(10)
      refute Process.alive?(subscriber)
    end

    test "stopping subscriber unsubscribes from topics" do
      topic = "test:unsubscribe"

      {:ok, subscriber} =
        start_test_subscriber(
          topics: [topic],
          test_pid: self()
        )

      Process.sleep(10)

      # Verify subscriber receives events
      event1 = DomainEvent.new(:before_stop, 1, :test, %{})
      :ok = publish_via_pubsub(event1, topic: topic)
      assert_event_handled(:before_stop)

      # Stop subscriber
      :ok = stop_test_subscriber(subscriber)
      Process.sleep(10)

      # Publish event - should not be received
      event2 = DomainEvent.new(:after_stop, 2, :test, %{})
      :ok = publish_via_pubsub(event2, topic: topic)

      refute_event_handled(100)
    end

    test "multiple stops are safe (idempotent)" do
      {:ok, subscriber} =
        start_test_subscriber(
          topics: ["test:idempotent"],
          test_pid: self()
        )

      # Stop multiple times - should not raise
      :ok = stop_test_subscriber(subscriber)
      :ok = stop_test_subscriber(subscriber)
      :ok = stop_test_subscriber(subscriber)
    end
  end

  describe "production subscriber isolation" do
    test "test subscribers do not interfere with production subscriber" do
      # The production ProviderEventHandler subscriber is started in application.ex
      production_subscriber =
        Process.whereis(:provider_integration_event_subscriber)

      {:ok, test_subscriber} =
        start_test_subscriber(
          topics: ["user:user_registered"],
          test_pid: self()
        )

      on_exit(fn -> stop_test_subscriber(test_subscriber) end)

      # Different PIDs
      assert production_subscriber != test_subscriber

      # Both should be alive
      if production_subscriber do
        assert Process.alive?(production_subscriber)
      end

      assert Process.alive?(test_subscriber)
    end

    test "test subscribers use unique names" do
      {:ok, subscriber1} =
        start_test_subscriber(
          topics: ["test:unique"],
          test_pid: self()
        )

      {:ok, subscriber2} =
        start_test_subscriber(
          topics: ["test:unique"],
          test_pid: self()
        )

      on_exit(fn ->
        stop_test_subscriber(subscriber1)
        stop_test_subscriber(subscriber2)
      end)

      # Both should be different processes
      assert subscriber1 != subscriber2
      assert Process.alive?(subscriber1)
      assert Process.alive?(subscriber2)
    end
  end

  describe "critical integration event handling" do
    test "wraps critical event handler in CriticalEventDispatcher" do
      handler = CriticalTestHandler

      {:ok, pid} =
        EventSubscriber.start_link(
          handler: handler,
          topics: ["integration:test:critical_test_event"],
          message_tag: :integration_event,
          event_label: "Integration event",
          name: :"critical_test_sub_#{System.unique_integer([:positive])}"
        )

      # Trigger: EventSubscriber runs in a separate process outside the test
      # Why: it needs DB access (via CriticalEventDispatcher) to write processed_events
      # Outcome: subscriber process shares the test's sandboxed DB connection
      Sandbox.allow(KlassHero.Repo, self(), pid)

      # Publish a critical integration event
      event =
        IntegrationEvent.new(:critical_test_event, :test, :entity, "ent-1", %{}, criticality: :critical)

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:test:critical_test_event",
        {:integration_event, event}
      )

      # Give the subscriber time to process
      Process.sleep(100)

      # Verify processed_events row was created
      handler_ref = CriticalEventDispatcher.handler_ref({handler, :handle_event})
      assert Repo.get_by(ProcessedEvent, event_id: event.event_id, handler_ref: handler_ref)
    end

    test "subscriber stays alive and no processed row when critical handler fails" do
      handler = CriticalFailingTestHandler

      {:ok, pid} =
        EventSubscriber.start_link(
          handler: handler,
          topics: ["integration:test:critical_test_event"],
          message_tag: :integration_event,
          event_label: "Integration event",
          name: :"critical_fail_sub_#{System.unique_integer([:positive])}"
        )

      Sandbox.allow(KlassHero.Repo, self(), pid)

      event =
        IntegrationEvent.new(:critical_test_event, :test, :entity, "ent-fail", %{}, criticality: :critical)

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:test:critical_test_event",
        {:integration_event, event}
      )

      Process.sleep(100)

      # Handler failed → transaction rolled back → no processed_events row
      assert [] == Repo.all(ProcessedEvent)
      # Subscriber GenServer stays alive after handler failure
      assert Process.alive?(pid)
    end

    test "logs differentiated crash message when dispatcher itself fails for critical event" do
      handler = CriticalTestHandler

      {:ok, pid} =
        EventSubscriber.start_link(
          handler: handler,
          topics: ["integration:test:critical_crash_event"],
          message_tag: :integration_event,
          event_label: "Integration event",
          name: :"critical_crash_sub_#{System.unique_integer([:positive])}"
        )

      Sandbox.allow(KlassHero.Repo, self(), pid)

      # Trigger: construct a critical event with nil event_id
      # Why: CriticalEventDispatcher.execute/3 guard `when is_binary(event_id)` will fail
      #      with FunctionClauseError, which propagates past handle_critical_event to
      #      the outer rescue block in handle_event_safely — the exact scenario C3 addresses
      # Outcome: rescue block detects critical event and logs with [CRITICAL EVENT HANDLER CRASH]
      event = %IntegrationEvent{
        event_id: nil,
        event_type: :critical_crash_event,
        source_context: :test,
        entity_type: :entity,
        entity_id: "ent-crash",
        occurred_at: DateTime.utc_now(),
        payload: %{},
        metadata: %{criticality: :critical}
      }

      log =
        ExUnit.CaptureLog.capture_log([level: :error], fn ->
          Phoenix.PubSub.broadcast(
            KlassHero.PubSub,
            "integration:test:critical_crash_event",
            {:integration_event, event}
          )

          Process.sleep(100)
        end)

      assert log =~ "CRITICAL EVENT HANDLER CRASH"
      assert log =~ "Durable Oban path will retry"
      assert Process.alive?(pid)
    end

    test "normal integration events bypass CriticalEventDispatcher" do
      handler = CriticalTestHandler

      {:ok, _pid} =
        EventSubscriber.start_link(
          handler: handler,
          topics: ["integration:test:critical_test_event"],
          message_tag: :integration_event,
          event_label: "Integration event",
          name: :"normal_test_sub_#{System.unique_integer([:positive])}"
        )

      # Publish a NORMAL integration event (no criticality)
      event =
        IntegrationEvent.new(:critical_test_event, :test, :entity, "ent-2", %{})

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:test:critical_test_event",
        {:integration_event, event}
      )

      Process.sleep(100)

      # No processed_events row — normal events bypass dispatcher
      assert [] == Repo.all(ProcessedEvent)
    end
  end
end
