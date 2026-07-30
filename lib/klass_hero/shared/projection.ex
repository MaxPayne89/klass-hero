defmodule KlassHero.Shared.Projection do
  @moduledoc """
  Base macro for event-driven projections.

  Injects `project/1`, plus a GenServer skeleton for bootstrap: `start_link/1`,
  `init/1`, `handle_continue(:bootstrap, _)`, `handle_call(:rebuild, ...)` and a
  catch-all `handle_info/2` warner. The calling module supplies `bootstrap_impl/0`
  and `handle_event/2`.

  The process exists to bootstrap and rebuild, not to receive events: integration
  events arrive as `project/1` calls from the outbox delivery job, in that job's
  process. `:topics` therefore declares what this projection consumes for the
  consumer registry to route, rather than what it subscribes to.

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
        def handle_event(:some_event, %Event{} = event) do
          # upsert into the read table
        end
      end

  See `KlassHero.Provider.Adapters.Driven.Projections.ProviderPrograms` for the
  canonical example.
  """

  alias KlassHero.Shared.Domain.Events.Event

  @callback bootstrap_impl() :: non_neg_integer()
  @callback handle_event(event_type :: atom(), event :: Event.t()) :: any()

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

      alias KlassHero.Shared.Domain.Events.Event
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
      @spec project(Event.t()) :: :ok
      def project(%Event{event_type: type} = event) do
        handle_event(type, event)
        :ok
      end

      def start_link(opts \\ []) do
        name = Keyword.get(opts, :name, __MODULE__)
        GenServer.start_link(__MODULE__, opts, name: name)
      end

      @impl true
      def init(opts) do
        # No subscriptions: every event reaches a projection through the outbox job
        # calling `project/1`. `@projection_topics` is now purely a declaration that
        # `EventConsumerRegistry` reads. This process exists for `bootstrap` and
        # `rebuild/1` only.
        if Keyword.get(opts, :skip_bootstrap, false) do
          {:ok, %{bootstrapped: false}}
        else
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
      def handle_info(:retry_bootstrap, state) do
        {:noreply, state, {:continue, :bootstrap}}
      end

      defoverridable apply_bootstrap: 1, handle_call: 3
    end
  end
end
