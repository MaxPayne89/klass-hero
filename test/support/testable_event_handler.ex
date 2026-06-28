defmodule KlassHero.TestableEventHandler do
  @moduledoc """
  Configurable event handler for integration testing.

  Sends received events to a configured test process and can simulate
  errors/crashes for testing EventSubscriber resilience.

  The handler uses the subscriber's PID (via `self()`) as the configuration key,
  since `handle_event/1` runs in the subscriber's process context.

  ## Usage

  In your test (via EventTestHelper):

      {:ok, subscriber} = start_test_subscriber(
        topics: ["user:user_registered"],
        test_pid: self(),
        behavior: :ok
      )

      on_exit(fn -> stop_test_subscriber(subscriber) end)

  ## Configuration Options

  - `:test_pid` - PID to send events to (receives `{:event_handled, event, handler_pid}`)
  - `:subscribed_events` - List of event types or [:all] (default: [:all])
  - `:behavior` - Handler behavior: :ok | :ignore | {:error, reason} | :crash
  """

  @behaviour KlassHero.Shared.Domain.Ports.Driving.ForHandlingEvents

  @table :testable_handler_config

  @doc """
  Initializes the ETS table for handler configuration.

  Called automatically when needed. Safe to call multiple times.
  """
  @spec init_config_table() :: :ok
  def init_config_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set])
    end

    :ok
  end

  @doc """
  Configures a handler instance identified by subscriber PID.

  ## Options

  - `:test_pid` - PID to receive `{:event_handled, event, handler_pid}` messages
  - `:subscribed_events` - List of event type atoms, or `[:all]` for all events
  - `:behavior` - One of:
    - `:ok` - Return :ok (default)
    - `:ignore` - Return :ignore
    - `{:error, reason}` - Return {:error, reason}
    - `:crash` - Raise an exception
  """
  @spec configure(pid(), keyword()) :: :ok
  def configure(subscriber_pid, opts) when is_pid(subscriber_pid) do
    init_config_table()

    config = %{
      test_pid: Keyword.get(opts, :test_pid),
      subscribed_events: Keyword.get(opts, :subscribed_events, [:all]),
      behavior: Keyword.get(opts, :behavior, :ok)
    }

    :ets.insert(@table, {subscriber_pid, config})
    :ok
  end

  @doc """
  Retrieves configuration for a handler instance by subscriber PID.
  """
  @spec get_config(pid()) :: map()
  def get_config(subscriber_pid) when is_pid(subscriber_pid) do
    init_config_table()

    case :ets.lookup(@table, subscriber_pid) do
      [{^subscriber_pid, config}] -> config
      [] -> %{subscribed_events: [:all], behavior: :ok, test_pid: nil}
    end
  end

  @doc """
  Clears configuration for a handler instance.
  """
  @spec clear_config(pid()) :: :ok
  def clear_config(subscriber_pid) when is_pid(subscriber_pid) do
    init_config_table()
    :ets.delete(@table, subscriber_pid)
    :ok
  end

  @doc """
  Clears all handler configurations.

  Useful in test setup/teardown.
  """
  @spec clear_all_configs() :: :ok
  def clear_all_configs do
    init_config_table()
    :ets.delete_all_objects(@table)
    :ok
  end

  @doc """
  Executes the configured test behavior for the calling process.

  Looks up the ETS config keyed by `self()` (the subscriber PID), notifies the
  test process, and returns the configured result. Shared by both
  `TestableEventHandler` and `TestableIntegrationEventHandler`.
  """
  @spec execute_configured_behavior(struct()) :: :ok | :ignore | {:error, term()}
  def execute_configured_behavior(event) do
    config = get_config(self())

    if config.test_pid && Process.alive?(config.test_pid) do
      send(config.test_pid, {:event_handled, event, self()})
    end

    case config.behavior do
      :ok -> :ok
      :ignore -> :ignore
      {:error, reason} -> {:error, reason}
      :crash -> raise "Simulated crash for testing"
    end
  end

  # ForHandlingEvents implementation
  # Note: handle_event/1 runs in the subscriber's process, so self() is the subscriber PID

  @impl true
  def subscribed_events do
    # This is used for documentation/introspection
    # Actual filtering happens in handle_event/1
    [:all]
  end

  @impl true
  def handle_event(event), do: execute_configured_behavior(event)
end
