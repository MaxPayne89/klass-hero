defmodule KlassHero.Shared.Projection do
  @moduledoc """
  Base macro for event-driven projections.

  Injects a GenServer skeleton: `start_link/1`, `init/1`, `handle_continue(:bootstrap, _)`,
  `handle_call(:rebuild, ...)`, an integration-event dispatcher, and a catch-all
  `handle_info/2` warner. The calling module supplies `bootstrap_impl/0` and
  `handle_event/2`.

  See `docs/superpowers/specs/2026-05-16-projection-macro-design.md`.
  """

  @callback bootstrap_impl() :: non_neg_integer()
  @callback handle_event(event_type :: atom(), event :: term()) :: any()

  defmacro __using__(opts) do
    topics = Keyword.fetch!(opts, :topics)

    quote bind_quoted: [topics: topics] do
      @behaviour KlassHero.Shared.Projection

      use GenServer

      require Logger

      @projection_topics topics

      def start_link(opts \\ []) do
        name = Keyword.get(opts, :name, __MODULE__)
        GenServer.start_link(__MODULE__, opts, name: name)
      end

      @impl GenServer
      def init(opts) do
        if Keyword.get(opts, :skip_bootstrap, false) do
          {:ok, %{bootstrapped: false}}
        else
          {:ok, %{bootstrapped: false}, {:continue, :bootstrap}}
        end
      end
    end
  end
end
