defmodule KlassHero.Shared.Projection.WithDomainEvents do
  @moduledoc """
  Opt-in mixin for `KlassHero.Shared.Projection`. Routes `{:domain_event, %DomainEvent{}}`
  envelopes received via PubSub to a `handle_domain_event/2` callback.

  Use immediately after `use KlassHero.Shared.Projection, ...` (and after
  `WithBootstrapRetry` if used).

  ## Usage

      defmodule MyContext.Adapters.Driven.Projections.MyProjection do
        use KlassHero.Shared.Projection, topics: ["..."]
        use KlassHero.Shared.Projection.WithBootstrapRetry
        use KlassHero.Shared.Projection.WithDomainEvents

        @impl KlassHero.Shared.Projection
        def bootstrap_impl, do: ...

        @impl KlassHero.Shared.Projection
        def handle_event(type, event), do: ...

        @impl KlassHero.Shared.Projection.WithDomainEvents
        def handle_domain_event(:some_domain_event, event), do: ...
      end
  """

  alias KlassHero.Shared.Domain.Events.DomainEvent

  @callback handle_domain_event(
              event_type :: atom(),
              event :: DomainEvent.t()
            ) :: any()

  defmacro __using__(_opts) do
    quote do
      @behaviour KlassHero.Shared.Projection.WithDomainEvents

      @impl true
      def handle_info({:domain_event, %DomainEvent{event_type: type} = event}, state) do
        Logger.debug("#{inspect(__MODULE__)} projecting domain event #{type}",
          aggregate_id: event.aggregate_id
        )

        handle_domain_event(type, event)
        {:noreply, state}
      end
    end
  end
end
