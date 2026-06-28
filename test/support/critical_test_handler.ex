defmodule KlassHero.Test.CriticalTestHandler do
  @moduledoc false

  @behaviour KlassHero.Shared.Domain.Ports.Driving.ForHandlingIntegrationEvents


  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  @impl true
  def subscribed_events, do: [:critical_test_event]

  @impl true
  def handle_event(%IntegrationEvent{} = _event), do: :ok
  def handle_event(_event), do: :ignore
end
