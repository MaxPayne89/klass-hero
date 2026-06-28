defmodule KlassHero.TestableIntegrationEventHandler do
  @moduledoc """
  Configurable integration event handler for integration testing.

  Mirrors `TestableEventHandler` but implements `ForHandlingIntegrationEvents`.
  Shares the same ETS configuration table as `TestableEventHandler`.

  ## Usage

  In your test (via EventTestHelper):

      {:ok, subscriber} = start_test_integration_subscriber(
        topics: ["integration:identity:child_data_anonymized"],
        test_pid: self(),
        behavior: :ok
      )

      on_exit(fn -> stop_test_subscriber(subscriber) end)
  """

  @behaviour KlassHero.Shared.Domain.Ports.Driving.ForHandlingIntegrationEvents

  alias KlassHero.TestableEventHandler

  @impl true
  def subscribed_events do
    [:all]
  end

  @impl true
  def handle_event(event), do: TestableEventHandler.execute_configured_behavior(event)
end
