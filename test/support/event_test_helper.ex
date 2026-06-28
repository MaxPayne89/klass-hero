defmodule KlassHero.EventTestHelper do
  @moduledoc """
  Test helpers for asserting on domain events.

  Provides convenient functions for testing event publishing in your tests,
  including integration test helpers for the full publish → subscribe → handle flow.

  ## Unit Test Setup (TestEventPublisher)

  For testing that events are published (without PubSub):

      setup do
        KlassHero.EventTestHelper.setup_test_events()
        :ok
      end

      test "publishes user_registered event" do
        user = insert(:user)
        EventPublisher.publish_user_registered(user)

        assert_event_published(:user_registered)
        assert_event_published(:user_registered, %{email: user.email})
      end

  ## Integration Test Setup (Real PubSub)

  For testing the full EventSubscriber → Handler flow:

      setup do
        {:ok, subscriber} = start_test_subscriber(
          topics: ["user:user_registered"],
          test_pid: self()
        )

        on_exit(fn -> stop_test_subscriber(subscriber) end)
        :ok
      end

      test "handler receives published event" do
        event = DomainEvent.new(:user_registered, 1, :user, %{})
        :ok = publish_via_pubsub(event)

        handled_event = assert_event_handled(:user_registered)
        assert handled_event.event_id == event.event_id
      end
  """

  import ExUnit.Assertions

  alias KlassHero.Shared.Adapters.Driven.Events.EventSubscriber
  alias KlassHero.Shared.Adapters.Driven.Events.PubSubEventPublisher
  alias KlassHero.Shared.Adapters.Driven.Events.PubSubIntegrationEventPublisher
  alias KlassHero.Shared.Adapters.Driven.Events.TestEventPublisher
  alias KlassHero.Shared.Adapters.Driven.Events.TestIntegrationEventPublisher
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.Domain.Events.IntegrationEvent
  alias KlassHero.TestableEventHandler
  alias KlassHero.TestableIntegrationEventHandler

  @doc """
  Initializes event collection for the current test.

  Call this in your test setup block.
  """
  @spec setup_test_events() :: :ok
  def setup_test_events do
    TestEventPublisher.setup()
  end

  @doc """
  Clears all collected events.

  Useful if you need to reset event state mid-test.
  """
  @spec clear_events() :: :ok
  def clear_events do
    TestEventPublisher.clear()
  end

  @doc """
  Returns all events published during the test.
  """
  @spec get_published_events() :: [DomainEvent.t()]
  def get_published_events do
    TestEventPublisher.get_events()
  end

  @doc """
  Asserts that an event of the given type was published.

  ## Examples

      assert_event_published(:user_registered)
      assert_event_published(:enrollment_confirmed)
  """
  @spec assert_event_published(atom()) :: DomainEvent.t()
  def assert_event_published(event_type) when is_atom(event_type) do
    events = get_published_events()

    event =
      Enum.find(events, fn %DomainEvent{event_type: type} ->
        type == event_type
      end)

    assert event != nil,
           "Expected event #{inspect(event_type)} to be published.\n" <>
             "Published events: #{format_event_types(events)}"

    event
  end

  @doc """
  Asserts that an event of the given type was published with a payload matching
  the expected fields.

  The payload match is partial - only the specified fields are checked.

  ## Examples

      assert_event_published(:user_registered, %{email: "test@example.com"})
      assert_event_published(:order_placed, %{total: 100, currency: "USD"})
  """
  @spec assert_event_published(atom(), map()) :: DomainEvent.t()
  def assert_event_published(event_type, expected_payload) when is_atom(event_type) and is_map(expected_payload) do
    events = get_published_events()

    event =
      Enum.find(events, fn %DomainEvent{event_type: type, payload: payload} ->
        type == event_type && payload_matches?(payload, expected_payload)
      end)

    if event == nil do
      matching_type_events =
        Enum.filter(events, fn %DomainEvent{event_type: type} ->
          type == event_type
        end)

      if matching_type_events == [] do
        flunk(
          "Expected event #{inspect(event_type)} to be published.\n" <>
            "Published events: #{format_event_types(events)}"
        )
      else
        flunk(
          "Expected event #{inspect(event_type)} with payload matching:\n" <>
            "  #{inspect(expected_payload)}\n\n" <>
            "Found #{length(matching_type_events)} event(s) of type #{inspect(event_type)}:\n" <>
            format_event_payloads(matching_type_events)
        )
      end
    end

    event
  end

  @doc """
  Asserts that no events were published.

  ## Examples

      assert_no_events_published()
  """
  @spec assert_no_events_published() :: :ok
  def assert_no_events_published do
    events = get_published_events()

    assert events == [],
           "Expected no events to be published.\n" <>
             "Published events: #{format_event_types(events)}"

    :ok
  end

  @doc """
  Asserts that exactly the given number of events were published.

  ## Examples

      assert_event_count(3)
  """
  @spec assert_event_count(non_neg_integer()) :: :ok
  def assert_event_count(expected_count) when is_integer(expected_count) do
    events = get_published_events()
    actual_count = length(events)

    assert actual_count == expected_count,
           "Expected #{expected_count} event(s) to be published, but got #{actual_count}.\n" <>
             "Published events: #{format_event_types(events)}"

    :ok
  end

  defp payload_matches?(actual, expected) do
    Enum.all?(expected, fn {key, value} ->
      Map.get(actual, key) == value
    end)
  end

  defp format_event_types([]), do: "(none)"
  defp format_event_types(events), do: Enum.map_join(events, ", ", &inspect(&1.event_type))

  defp format_event_payloads(events) do
    events
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {event, idx} -> "  #{idx}. #{inspect(event.payload)}" end)
  end

  # ===========================================================================
  # Integration Event Unit Test Helpers (TestIntegrationEventPublisher)
  # ===========================================================================

  @doc """
  Initializes integration event collection for the current test.

  Call this in your test setup block.
  """
  @spec setup_test_integration_events() :: :ok
  def setup_test_integration_events do
    TestIntegrationEventPublisher.setup()
  end

  @doc """
  Clears all collected integration events.
  """
  @spec clear_integration_events() :: :ok
  def clear_integration_events do
    TestIntegrationEventPublisher.clear()
  end

  @doc """
  Returns all integration events published during the test.
  """
  @spec get_published_integration_events() :: [IntegrationEvent.t()]
  def get_published_integration_events do
    TestIntegrationEventPublisher.get_events()
  end

  @doc """
  Asserts that an integration event of the given type was published.

  ## Examples

      assert_integration_event_published(:child_data_anonymized)
  """
  @spec assert_integration_event_published(atom()) :: IntegrationEvent.t()
  def assert_integration_event_published(event_type) when is_atom(event_type) do
    events = get_published_integration_events()

    event =
      Enum.find(events, fn %IntegrationEvent{event_type: type} ->
        type == event_type
      end)

    assert event != nil,
           "Expected integration event #{inspect(event_type)} to be published.\n" <>
             "Published integration events: #{format_event_types(events)}"

    event
  end

  @doc """
  Asserts that an integration event of the given type was published with a payload
  matching the expected fields.

  The payload match is partial - only the specified fields are checked.

  ## Examples

      assert_integration_event_published(:child_data_anonymized, %{child_id: "uuid"})
  """
  @spec assert_integration_event_published(atom(), map()) :: IntegrationEvent.t()
  def assert_integration_event_published(event_type, expected_payload)
      when is_atom(event_type) and is_map(expected_payload) do
    events = get_published_integration_events()

    event =
      Enum.find(events, fn %IntegrationEvent{event_type: type, payload: payload} ->
        type == event_type && payload_matches?(payload, expected_payload)
      end)

    if event == nil do
      matching_type_events =
        Enum.filter(events, fn %IntegrationEvent{event_type: type} ->
          type == event_type
        end)

      if matching_type_events == [] do
        flunk(
          "Expected integration event #{inspect(event_type)} to be published.\n" <>
            "Published integration events: #{format_event_types(events)}"
        )
      else
        flunk(
          "Expected integration event #{inspect(event_type)} with payload matching:\n" <>
            "  #{inspect(expected_payload)}\n\n" <>
            "Found #{length(matching_type_events)} event(s) of type #{inspect(event_type)}:\n" <>
            format_event_payloads(matching_type_events)
        )
      end
    end

    event
  end

  @doc """
  Asserts that no integration events were published.
  """
  @spec assert_no_integration_events_published() :: :ok
  def assert_no_integration_events_published do
    events = get_published_integration_events()

    assert events == [],
           "Expected no integration events to be published.\n" <>
             "Published integration events: #{format_event_types(events)}"

    :ok
  end

  @doc """
  Asserts that exactly the given number of integration events were published.
  """
  @spec assert_integration_event_count(non_neg_integer()) :: :ok
  def assert_integration_event_count(expected_count) when is_integer(expected_count) do
    events = get_published_integration_events()
    actual_count = length(events)

    assert actual_count == expected_count,
           "Expected #{expected_count} integration event(s) to be published, but got #{actual_count}.\n" <>
             "Published integration events: #{format_event_types(events)}"

    :ok
  end

  # ===========================================================================
  # Integration Test Helpers (Real PubSub) — Domain Events
  # ===========================================================================

  @doc """
  Starts a test EventSubscriber with TestableEventHandler.

  The subscriber uses the real PubSub for message passing, enabling
  integration tests of the full publish → subscribe → handle flow.

  Returns `{:ok, subscriber_pid}` on success.

  ## Options

  - `:topics` - (required) List of topic strings to subscribe to
  - `:test_pid` - PID to receive `{:event_handled, event, handler_pid}` messages (default: `self()`)
  - `:behavior` - Handler behavior: `:ok` | `:ignore` | `{:error, reason}` | `:crash` (default: `:ok`)
  - `:pubsub` - PubSub server name (default: `KlassHero.PubSub`)

  ## Example

      {:ok, subscriber} = start_test_subscriber(
        topics: ["user:user_registered", "user:user_confirmed"],
        test_pid: self(),
        behavior: :ok
      )

      on_exit(fn -> stop_test_subscriber(subscriber) end)
  """
  @spec start_test_subscriber(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_test_subscriber(opts) do
    topics = Keyword.fetch!(opts, :topics)
    test_pid = Keyword.get(opts, :test_pid, self())
    behavior = Keyword.get(opts, :behavior, :ok)
    pubsub = Keyword.get(opts, :pubsub, KlassHero.PubSub)

    # Generate unique name to avoid conflicts with production subscriber
    name = :"test_subscriber_#{:erlang.unique_integer([:positive])}"

    subscriber_opts = [
      handler: TestableEventHandler,
      topics: topics,
      pubsub: pubsub,
      name: name
    ]

    case GenServer.start_link(EventSubscriber, subscriber_opts, name: name) do
      {:ok, pid} ->
        # Configure the handler with the subscriber's PID as the key
        TestableEventHandler.configure(pid,
          test_pid: test_pid,
          behavior: behavior
        )

        {:ok, pid}

      error ->
        error
    end
  end

  @doc """
  Stops a test subscriber and cleans up its configuration.

  ## Example

      stop_test_subscriber(subscriber)
  """
  @spec stop_test_subscriber(pid()) :: :ok
  def stop_test_subscriber(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      TestableEventHandler.clear_config(pid)
      GenServer.stop(pid, :normal, 1000)
    end

    :ok
  catch
    :exit, _ -> :ok
  end

  @doc """
  Publishes an event via PubSub (bypassing TestEventPublisher).

  For integration tests that need real PubSub broadcasting.

  ## Options

  - `:topic` - Override the topic (default: derived from event via `derive_topic/1`)
  - `:pubsub` - PubSub server name (default: `KlassHero.PubSub`)

  ## Example

      event = DomainEvent.new(:user_registered, 1, :user, %{email: "test@example.com"})
      :ok = publish_via_pubsub(event)

      # Or with custom topic
      :ok = publish_via_pubsub(event, topic: "custom:topic")
  """
  @spec publish_via_pubsub(DomainEvent.t(), keyword()) :: :ok | {:error, term()}
  def publish_via_pubsub(%DomainEvent{} = event, opts \\ []) do
    pubsub = Keyword.get(opts, :pubsub, KlassHero.PubSub)

    topic =
      Keyword.get_lazy(opts, :topic, fn ->
        PubSubEventPublisher.derive_topic(event)
      end)

    Phoenix.PubSub.broadcast(pubsub, topic, {:domain_event, event})
  end

  @doc """
  Asserts that an event was handled by the test handler.

  Waits for the handler to send `{:event_handled, event, handler_pid}`.
  Returns the handled event on success.

  ## Parameters

  - `event_type` - The expected event type atom
  - `timeout` - Maximum wait time in milliseconds (default: 500)

  ## Example

      handled_event = assert_event_handled(:user_registered)
      assert handled_event.payload.email == "test@example.com"

      # With custom timeout
      assert_event_handled(:slow_event, 1000)
  """
  @spec assert_event_handled(atom(), timeout()) :: DomainEvent.t()
  def assert_event_handled(event_type, timeout \\ 500) when is_atom(event_type) do
    receive do
      {:event_handled, %DomainEvent{event_type: ^event_type} = event, _pid} ->
        event
    after
      timeout ->
        flunk("Expected event #{inspect(event_type)} to be handled within #{timeout}ms")
    end
  end

  @doc """
  Asserts that an event was handled with a payload matching expected fields.

  The payload match is partial - only the specified fields are checked.

  ## Example

      assert_event_handled(:user_registered, %{email: "test@example.com"})
  """
  @spec assert_event_handled(atom(), map(), timeout()) :: DomainEvent.t()
  def assert_event_handled(event_type, expected_payload, timeout)
      when is_atom(event_type) and is_map(expected_payload) do
    receive do
      {:event_handled, %DomainEvent{event_type: ^event_type, payload: payload} = event, _pid} ->
        if payload_matches?(payload, expected_payload) do
          event
        else
          flunk(
            "Expected event #{inspect(event_type)} with payload matching:\n" <>
              "  #{inspect(expected_payload)}\n\n" <>
              "Got:\n  #{inspect(payload)}"
          )
        end
    after
      timeout ->
        flunk("Expected event #{inspect(event_type)} to be handled within #{timeout}ms")
    end
  end

  @doc """
  Asserts that no events were handled within the timeout.

  ## Parameters

  - `timeout` - Wait time in milliseconds (default: 100)

  ## Example

      # Assert no events received
      refute_event_handled()

      # With longer timeout
      refute_event_handled(200)
  """
  @spec refute_event_handled(timeout()) :: :ok
  def refute_event_handled(timeout \\ 100) do
    receive do
      {:event_handled, %DomainEvent{event_type: event_type}, _pid} ->
        flunk("Expected no events to be handled, but received #{inspect(event_type)}")
    after
      timeout -> :ok
    end
  end

  # ===========================================================================
  # Integration Event PubSub Helpers (Real PubSub)
  # ===========================================================================

  @doc """
  Publishes an integration event via PubSub (bypassing TestIntegrationEventPublisher).

  For integration tests that need real PubSub broadcasting of integration events.

  ## Options

  - `:topic` - Override the topic (default: derived from event via `derive_topic/1`)
  - `:pubsub` - PubSub server name (default: `KlassHero.PubSub`)

  ## Example

      event = IntegrationEvent.new(:child_data_anonymized, :identity, :child, "uuid", %{})
      :ok = publish_integration_event_via_pubsub(event)
  """
  @spec publish_integration_event_via_pubsub(IntegrationEvent.t(), keyword()) ::
          :ok | {:error, term()}
  def publish_integration_event_via_pubsub(%IntegrationEvent{} = event, opts \\ []) do
    pubsub = Keyword.get(opts, :pubsub, KlassHero.PubSub)

    topic =
      Keyword.get_lazy(opts, :topic, fn ->
        PubSubIntegrationEventPublisher.derive_topic(event)
      end)

    Phoenix.PubSub.broadcast(pubsub, topic, {:integration_event, event})
  end

  @doc """
  Starts a test EventSubscriber (integration mode) with TestableIntegrationEventHandler.

  Returns `{:ok, subscriber_pid}` on success.

  ## Options

  - `:topics` - (required) List of topic strings to subscribe to
  - `:test_pid` - PID to receive messages (default: `self()`)
  - `:behavior` - Handler behavior (default: `:ok`)
  - `:pubsub` - PubSub server name (default: `KlassHero.PubSub`)
  """
  @spec start_test_integration_subscriber(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_test_integration_subscriber(opts) do
    topics = Keyword.fetch!(opts, :topics)
    test_pid = Keyword.get(opts, :test_pid, self())
    behavior = Keyword.get(opts, :behavior, :ok)
    pubsub = Keyword.get(opts, :pubsub, KlassHero.PubSub)

    name = :"test_integration_subscriber_#{:erlang.unique_integer([:positive])}"

    subscriber_opts = [
      handler: TestableIntegrationEventHandler,
      topics: topics,
      pubsub: pubsub,
      name: name,
      message_tag: :integration_event,
      event_label: "Integration event"
    ]

    case GenServer.start_link(EventSubscriber, subscriber_opts, name: name) do
      {:ok, pid} ->
        TestableEventHandler.configure(pid,
          test_pid: test_pid,
          behavior: behavior
        )

        {:ok, pid}

      error ->
        error
    end
  end
end
