defmodule KlassHero.Shared.ForHandlingEvents do
  @moduledoc """
  Behaviour for domain event handlers.

  Implement this behaviour to create event handlers that react to domain events
  published via PubSub (e.g. Accounts context broadcasting user lifecycle events).
  For cross-context integration events, see `ForHandlingIntegrationEvents`.

  ## Example

      defmodule MyApp.Family.UserEventHandler do
        @behaviour KlassHero.Shared.ForHandlingEvents

        @impl true
        def subscribed_events, do: [:user_registered, :user_confirmed]

        @impl true
        def handle_event(%{event_type: :user_registered} = event) do
          :ok
        end

        def handle_event(%{event_type: :user_confirmed} = _event) do
          :ok
        end

        def handle_event(_event), do: :ignore
      end
  """

  alias KlassHero.Shared.Domain.Events.DomainEvent

  @doc """
  Handles a domain event.

  Returns:
  - `:ok` - Event handled successfully
  - `{:error, reason}` - Handling failed (will be logged)
  - `:ignore` - Event was intentionally ignored
  """
  @callback handle_event(DomainEvent.t()) :: :ok | {:error, term()} | :ignore

  @doc """
  Returns the list of event types this handler subscribes to.

  Return `[:all]` to receive all events (use sparingly).
  """
  @callback subscribed_events() :: [atom()] | [:all]
end
