defmodule KlassHero.Shared.ForHandlingIntegrationEvents do
  @moduledoc """
  Behaviour for integration event handlers.

  Implement this behaviour to handle integration events from other bounded
  contexts. Integration events are the public contract between contexts —
  they carry stable, versioned payloads.

  ## Example

      defmodule MyApp.Participation.ChildAnonymizedHandler do
        @behaviour KlassHero.Shared.ForHandlingIntegrationEvents

        @impl true
        def subscribed_events, do: [:child_data_anonymized]

        @impl true
        def handle_event(%IntegrationEvent{event_type: :child_data_anonymized} = event) do
          :ok
        end

        def handle_event(_event), do: :ignore
      end
  """

  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  @doc """
  Handles an integration event. Returns `:ok`, `{:error, reason}`, or `:ignore`.
  """
  @callback handle_event(IntegrationEvent.t()) :: :ok | {:error, term()} | :ignore

  @doc """
  Returns the list of event types this handler subscribes to.

  Return `[:all]` to receive all events (use sparingly).
  """
  @callback subscribed_events() :: [atom()] | [:all]
end
