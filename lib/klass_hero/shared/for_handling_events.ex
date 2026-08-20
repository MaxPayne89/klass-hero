defmodule KlassHero.Shared.ForHandlingEvents do
  @moduledoc """
  Behaviour for event handlers.

  Implement this behaviour to handle events the delivery job routes to you —
  usually another context's, since an event is the public contract between
  contexts.

  ## Routing is config, not this behaviour

  Implementing this behaviour does **not** subscribe you to anything.
  `EventDeliveryWorker` resolves consumers solely through
  `EventConsumerRegistry.consumers_for/1`, which reads the `:event_consumers`
  map in `config/config.exs`. Nothing calls `subscribed_events/0` at runtime.

  A handler is wired when, and only when, it appears under its topic there:

      "integration:provider:staff_member_invited" => [
        {StaffInvitationHandler, :handle_event}
      ]

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
  Declares the event types this handler expects to be routed.

  This is a declaration checked against config, not a subscription — see the
  moduledoc. `event_consumer_wiring_test.exs` asserts it agrees with the topics
  `:event_consumers` actually routes here, which is what catches the silent
  failure of adding a `handle_event/1` clause and forgetting the registry entry.
  """
  @callback subscribed_events() :: [atom()]
end
