defmodule KlassHero.Shared.Projection do
  @moduledoc """
  Base macro for event-driven projections.

  Injects a GenServer skeleton: `start_link/1`, `init/1`, `handle_continue(:bootstrap, _)`,
  `handle_call(:rebuild, ...)`, an integration-event dispatcher, and a catch-all
  `handle_info/2` warner. The calling module supplies `bootstrap_impl/0` and
  `handle_event/2`.

  ## Usage

      defmodule MyContext.Adapters.Driven.Projections.MyProjection do
        use KlassHero.Shared.Projection,
          topics: ["integration:some_context:some_event"]

        # Optionally add retry on transient bootstrap failure:
        use KlassHero.Shared.Projection.WithBootstrapRetry

        @impl KlassHero.Shared.Projection
        def bootstrap_impl do
          # populate the read table; return row count
          42
        end

        @impl KlassHero.Shared.Projection
        def handle_event(:some_event, %IntegrationEvent{} = event) do
          # upsert into the read table
        end
      end

  See `KlassHero.Provider.Adapters.Driven.Projections.ProviderPrograms` for the
  canonical example.
  """

  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  @callback bootstrap_impl() :: non_neg_integer()
  @callback handle_event(event_type :: atom(), event :: IntegrationEvent.t()) :: any()

  defmacro __before_compile__(_env) do
    quote do
      @impl true
      def handle_info(msg, state) do
        Logger.warning("#{inspect(__MODULE__)} received unexpected message",
          message: inspect(msg, limit: 200)
        )

        {:noreply, state}
      end
    end
  end

  defmacro __using__(opts) do
    topics = Keyword.fetch!(opts, :topics)

    quote bind_quoted: [topics: topics] do
      @behaviour KlassHero.Shared.Projection

      use GenServer

      alias KlassHero.Shared.Domain.Events.IntegrationEvent
      alias KlassHero.Shared.Projection

      require Logger

      @before_compile Projection

      @projection_topics topics

      @doc """
      Topics this projection consumes. Read by the consumer-registry coverage test.
      """
      @spec topics() :: [String.t()]
      def topics, do: @projection_topics

      @doc """
      Projects one integration event in the caller's process.

      The entry point the outbox delivery job calls, which is why it takes the
      whole event rather than `(type, event)` — it makes a projection shaped like
      every other consumer in the registry.
      """
      @spec project(IntegrationEvent.t()) :: :ok
      def project(%IntegrationEvent{event_type: type} = event) do
        handle_event(type, event)
        :ok
      end

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

      @impl true
      def handle_info(:retry_bootstrap, state) do
        {:noreply, state, {:continue, :bootstrap}}
      end

      defoverridable apply_bootstrap: 1, handle_call: 3
    end
  end
end
