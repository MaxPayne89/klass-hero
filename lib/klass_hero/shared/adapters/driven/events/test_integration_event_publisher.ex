defmodule KlassHero.Shared.Adapters.Driven.Events.TestIntegrationEventPublisher do
  @moduledoc """
  Test implementation of the ForPublishingIntegrationEvents port.

  Collects published integration events in the process dictionary for test assertions.
  Each test process has its own isolated event collection, making it safe
  for concurrent test execution.

  ## Usage

  In your test setup:

      setup do
        KlassHero.Shared.Adapters.Driven.Events.TestIntegrationEventPublisher.setup()
        :ok
      end

  Or use the EventTestHelper which wraps this:

      setup do
        KlassHero.EventTestHelper.setup_test_integration_events()
        :ok
      end

  Then in your test:

      test "publishes integration event" do
        # ... trigger event publishing ...

        events = TestIntegrationEventPublisher.get_events()
        assert length(events) == 1
      end
  """

  @behaviour KlassHero.Shared.ForPublishingIntegrationEvents

  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  @key :test_published_integration_events
  @error_key :test_integration_event_publish_error

  @doc """
  Initializes the integration event collection for the current test process.

  Call this in your test setup to enable event collection.
  """
  @spec setup() :: :ok
  def setup do
    Process.put(@key, [])
    Process.delete(@error_key)
    :ok
  end

  @doc """
  Clears all collected integration events for the current test process.
  """
  @spec clear() :: :ok
  def clear do
    Process.put(@key, [])
    Process.delete(@error_key)
    :ok
  end

  @doc """
  Configures publish/1 to return `{:error, reason}` for subsequent calls.

  Uses process dictionary so it's isolated per test process.

  ## Example

      configure_publish_error(:pubsub_down)
      assert {:error, :pubsub_down} = IntegrationEventPublishing.publish(event)
  """
  @spec configure_publish_error(term()) :: :ok
  def configure_publish_error(reason) do
    Process.put(@error_key, reason)
    :ok
  end

  @doc """
  Returns all integration events published in the current test process, without
  their topics.

  Returns an empty list if setup() was not called.
  """
  @spec get_events() :: [IntegrationEvent.t()]
  def get_events do
    for {event, _topic} <- get_published(), do: event
  end

  @doc """
  Returns `{event, topic}` tuples for every integration event published in the
  current test process, in publish order.

  The topic is the exact `integration:<context>:<event>` string the event was
  routed on — added for #1122 (mirroring #1108 on the domain-event axis) so tests
  can assert the producer/consumer topic coupling of the `critical_event_handlers`
  registry rather than pinning topic literals by hand. Events published via
  `publish/1` carry their derived topic.
  """
  @spec get_published() :: [{IntegrationEvent.t(), String.t()}]
  def get_published do
    Process.get(@key, [])
  end

  @impl true
  def publish(%IntegrationEvent{} = event) do
    case Process.get(@error_key) do
      nil ->
        store_event(event, IntegrationEvent.topic(event))
        :ok

      reason ->
        {:error, reason}
    end
  end

  @impl true
  def publish(%IntegrationEvent{} = event, topic) do
    case Process.get(@error_key) do
      nil ->
        store_event(event, topic)
        :ok

      reason ->
        {:error, reason}
    end
  end

  @impl true
  def publish_all(events) when is_list(events) do
    Enum.each(events, &store_event(&1, IntegrationEvent.topic(&1)))
    :ok
  end

  defp store_event(%IntegrationEvent{} = event, topic) do
    published = Process.get(@key, [])
    Process.put(@key, published ++ [{event, topic}])
  end
end
