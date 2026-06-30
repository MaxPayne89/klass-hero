defmodule KlassHero.Participation.Adapters.Driving.Events.EventHandlers.SeedSessionRosterHandler do
  @moduledoc """
  Integration event handler that seeds session rosters when sessions are created.

  Subscribes to `session_created` integration events on PubSub and delegates
  to the SeedSessionRoster use case.

  ## Architecture

  ```
  PubSub "integration:participation:session_created"
    → EventSubscriber (shared GenServer)
    → [THIS HANDLER] handle_event/1
    → SeedSessionRoster.execute/2
  ```

  ## Error Strategy

  The use case is best-effort — errors are logged and swallowed.
  """

  @behaviour KlassHero.Shared.Domain.Ports.Driving.ForHandlingIntegrationEvents

  alias KlassHero.Participation
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  @impl true
  def subscribed_events, do: [:session_created]

  @impl true
  def handle_event(%IntegrationEvent{event_type: :session_created, payload: payload}) do
    Participation.seed_session_roster(payload.session_id, payload.program_id)
  end

  def handle_event(_event), do: :ignore
end
