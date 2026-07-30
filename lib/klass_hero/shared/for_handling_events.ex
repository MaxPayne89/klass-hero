defmodule KlassHero.Shared.ForHandlingEvents do
  @moduledoc """
  Behaviour for event handlers.

  Implement this behaviour to handle events the delivery job routes to you —
  usually another context's, since an event is the public contract between
  contexts.

  ## Example

      defmodule MyApp.Participation.ChildAnonymizedHandler do
        @behaviour KlassHero.Shared.ForHandlingEvents

        @impl true
        def subscribed_events, do: [:child_data_anonymized]

        @impl true
        def handle_event(%Event{event_type: :child_data_anonymized} = event) do
          :ok
        end

        def handle_event(_event), do: :ignore
      end
  """

  alias KlassHero.Shared.Domain.Events.Event

  @doc """
  Handles an integration event. Returns `:ok`, `{:error, reason}`, or `:ignore`.
  """
  @callback handle_event(Event.t()) :: :ok | {:error, term()} | :ignore

  @doc """
  Returns the list of event types this handler subscribes to.

  Return `[:all]` to receive all events (use sparingly).
  """
  @callback subscribed_events() :: [atom()] | [:all]
end
