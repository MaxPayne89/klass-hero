defmodule KlassHero.Shared.Adapters.Driven.Events.TestEventPublisher do
  @moduledoc """
  Test implementation of the ForPublishingEvents port.

  Collects published events in the process dictionary for test assertions.
  Each test process has its own isolated event collection, making it safe
  for concurrent test execution.

  ## Usage

  In your test setup:

      setup do
        KlassHero.Shared.Adapters.Driven.Events.TestEventPublisher.setup()
        :ok
      end

  Or use the EventTestHelper which wraps this:

      setup do
        KlassHero.EventTestHelper.setup_test_events()
        :ok
      end

  Then in your test:

      test "publishes event" do
        # ... trigger event publishing ...

        events = TestEventPublisher.get_events()
        assert length(events) == 1
      end
  """

  @behaviour KlassHero.Shared.ForPublishingEvents

  alias KlassHero.Shared.Domain.Events.DomainEvent

  @key :test_published_events

  @doc """
  Initializes the event collection for the current test process.

  Call this in your test setup to enable event collection.
  """
  @spec setup() :: :ok
  def setup do
    Process.put(@key, [])
    :ok
  end

  @doc """
  Clears all collected events for the current test process.
  """
  @spec clear() :: :ok
  def clear do
    Process.put(@key, [])
    :ok
  end

  @doc """
  Returns all events published in the current test process, without their topics.

  Returns an empty list if setup() was not called.
  """
  @spec get_events() :: [DomainEvent.t()]
  def get_events do
    for {event, _topic} <- get_published(), do: event
  end

  @doc """
  Returns `{event, topic}` tuples for everything published in the current test
  process, in publish order.

  The topic is the exact string the event was broadcast on — added for #1108 so
  tests can assert the publish→subscribe coupling rather than pinning topic
  literals by hand. Events published via `publish/1` carry their derived topic.
  """
  @spec get_published() :: [{DomainEvent.t(), String.t()}]
  def get_published do
    Process.get(@key, [])
  end

  @impl true
  def publish(%DomainEvent{} = event) do
    store_event(event, derive_topic(event))
    :ok
  end

  @impl true
  def publish(%DomainEvent{} = event, topic) do
    store_event(event, topic)
    :ok
  end

  @impl true
  def publish_all(events) when is_list(events) do
    Enum.each(events, &store_event(&1, derive_topic(&1)))
    :ok
  end

  defp store_event(%DomainEvent{} = event, topic) do
    published = Process.get(@key, [])
    Process.put(@key, published ++ [{event, topic}])
  end

  defp derive_topic(%DomainEvent{aggregate_type: aggregate_type, event_type: event_type}) do
    "#{aggregate_type}:#{event_type}"
  end
end
