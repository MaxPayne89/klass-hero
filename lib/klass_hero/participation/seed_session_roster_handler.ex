defmodule KlassHero.Participation.SeedSessionRosterHandler do
  @moduledoc """
  Integration event handler that seeds session rosters when sessions are created.

  Subscribes to `session_created` integration events on PubSub and delegates
  to the SeedSessionRoster use case.

  ## Architecture

  ```
  staged "integration:participation:session_created"
    → EventDeliveryWorker (Oban, retries on failure)
    → [THIS HANDLER] handle_event/1
    → SeedSessionRoster.execute/2
  ```

  ## Error Strategy

  The use case is best-effort — errors are logged and swallowed.
  """

  @behaviour KlassHero.Shared.ForHandlingEvents

  alias KlassHero.Participation
  alias KlassHero.Shared.Domain.Events.Event

  @impl true
  def subscribed_events, do: [:session_created, :sessions_generated]

  @impl true
  def handle_event(%Event{event_type: :session_created, payload: payload}) do
    Participation.seed_session_roster(payload.session_id, payload.program_id)
  end

  # A schedule-derived batch shares one program, so the enrolled children are
  # resolved once for the whole batch rather than once per session.
  def handle_event(%Event{event_type: :sessions_generated, payload: %{program_id: program_id, sessions: sessions}}) do
    Participation.seed_rosters_for_sessions(Enum.map(sessions, & &1.session_id), program_id)
  end

  def handle_event(_event), do: :ignore
end
