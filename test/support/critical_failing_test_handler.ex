defmodule KlassHero.Test.CriticalFailingTestHandler do
  @moduledoc false

  @behaviour KlassHero.Shared.ForHandlingEvents

  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  @impl true
  def subscribed_events, do: [:critical_test_event]

  @impl true
  def handle_event(%IntegrationEvent{} = _event), do: {:error, :handler_rejected}

  def handle_event(_event), do: :ignore
end
