defmodule KlassHero.Shared.Projection do
  @moduledoc """
  Base macro for event-driven projections.

  Injects a GenServer skeleton: `start_link/1`, `init/1`, `handle_continue(:bootstrap, _)`,
  `handle_call(:rebuild, ...)`, an integration-event dispatcher, and a catch-all
  `handle_info/2` warner. The calling module supplies `bootstrap_impl/0` and
  `handle_event/2`.

  See `docs/superpowers/specs/2026-05-16-projection-macro-design.md`.
  """

  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  @callback bootstrap_impl() :: non_neg_integer()
  @callback handle_event(event_type :: atom(), event :: IntegrationEvent.t()) :: any()

  defmacro __using__(opts) do
    topics = Keyword.fetch!(opts, :topics)

    quote bind_quoted: [topics: topics] do
      @behaviour KlassHero.Shared.Projection

      use GenServer

      alias KlassHero.Shared.Domain.Events.IntegrationEvent

      require Logger

      @projection_topics topics

      def start_link(opts \\ []) do
        name = Keyword.get(opts, :name, __MODULE__)
        GenServer.start_link(__MODULE__, opts, name: name)
      end

      @impl true
      def init(opts) do
        if Keyword.get(opts, :skip_bootstrap, false) do
          {:ok, %{bootstrapped: false}}
        else
          for topic <- @projection_topics do
            Phoenix.PubSub.subscribe(KlassHero.PubSub, topic)
          end

          {:ok, %{bootstrapped: false}, {:continue, :bootstrap}}
        end
      end

      @impl true
      def handle_continue(:bootstrap, state), do: apply_bootstrap(state)

      defp apply_bootstrap(state) do
        count = bootstrap_impl()
        Logger.info("#{inspect(__MODULE__)} projection started", count: count)
        {:noreply, %{state | bootstrapped: true}}
      end

      @spec rebuild(GenServer.name()) :: :ok
      def rebuild(name \\ __MODULE__) do
        GenServer.call(name, :rebuild, :infinity)
      end

      @impl true
      def handle_call(:rebuild, _from, state) do
        count = bootstrap_impl()
        Logger.info("#{inspect(__MODULE__)} rebuilt", count: count)
        {:reply, :ok, %{state | bootstrapped: true}}
      end

      @impl true
      def handle_info({:integration_event, %IntegrationEvent{event_type: type} = event}, state) do
        Logger.debug("#{inspect(__MODULE__)} projecting #{type}",
          entity_id: event.entity_id,
          event_id: event.event_id
        )

        handle_event(type, event)
        {:noreply, state}
      end

      defoverridable apply_bootstrap: 1
    end
  end
end
