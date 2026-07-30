defmodule KlassHero.Shared.DomainEventBus do
  @moduledoc """
  Per-context handler registry for dispatching internal domain events.

  The GenServer acts as a registry only — it stores handler registrations and
  serves them on request. Actual handler execution happens in the caller's
  process via `dispatch/2`, preserving process context (process dictionary,
  test doubles, etc.).

  Each bounded context can have its own DomainEventBus for events that are
  internal to the context and should not cross context boundaries. Unlike
  integration events (which use PubSub), domain events are dispatched
  synchronously to registered handlers within the same process that calls
  `dispatch/2`.

  ## Usage

  Add to your application's supervision tree:

      {KlassHero.Shared.DomainEventBus, context: KlassHero.Family}

  With init-time handler registration:

      {KlassHero.Shared.DomainEventBus,
       context: KlassHero.Family,
       handlers: [
         {:child_updated, {MyHandler, :handle_child_updated}},
         {:user_deleted, {MyHandler, :handle_user_deleted}, priority: 10}
       ]}

  ## Subscribing

      DomainEventBus.subscribe(KlassHero.Family, :child_updated, fn event ->
        # handle event
        :ok
      end)

      # With priority (lower number runs first, default 100)
      DomainEventBus.subscribe(KlassHero.Family, :child_updated, handler_fn, priority: 10)

  ### Subscriptions are owned by the calling process

  A bus is a globally-named singleton per context, so without scoping every
  runtime subscription would hear every dispatch in the VM — including those of
  concurrent `async: true` tests, which is what made #1136 flaky.

  A `subscribe/4` handler therefore fires only for dispatches from its owning
  process or a `Task` descendant of it, and is dropped when that process exits.
  Handlers registered at boot via `handlers:` are exempt and always fire, so
  production delivery is unaffected. See `subscribe/4` for the full contract.

  ## Dispatching

      DomainEventBus.dispatch(KlassHero.Family, %DomainEvent{event_type: :child_updated, ...})
  """

  use GenServer

  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  require Logger

  @typedoc """
  Either event struct, while the two tiers are being collapsed into one (ADR-0014
  PR 5). The bus reads only `event_type`, so it never cared which it was; the
  union is temporary and narrows to one struct once `DomainEvent` is deleted.
  """
  @type dispatchable :: DomainEvent.t() | IntegrationEvent.t()

  @default_priority 100

  defstruct context: nil, handlers: %{}

  @doc """
  Starts the DomainEventBus for a given context.

  ## Options

  - `:context` - (required) The bounded context module (e.g., `KlassHero.Family`)
  - `:handlers` - (optional) List of init-time handler specs:
    - `{event_type, {Module, :function}}` — registers with default priority
    - `{event_type, {Module, :function}, opts}` — registers with given opts (e.g. `priority: 10`)
  """
  def start_link(opts) do
    context = Keyword.fetch!(opts, :context)
    handlers_spec = Keyword.get(opts, :handlers, [])
    name = process_name(context)

    GenServer.start_link(__MODULE__, %{context: context, handlers_spec: handlers_spec}, name: name)
  end

  @doc """
  Subscribes a handler function to a specific event type on the given context's bus.

  The handler function receives a `%DomainEvent{}` and should return `:ok`.

  ## Options

  - `:priority` - Integer priority (lower runs first, default #{@default_priority})
  - `:mode` - Reserved for future async support (default `:sync`)

  ## Warning — subscriptions are owned by the calling process

  A handler registered here fires **only** for events dispatched from the
  subscribing process, or from a process descended from it via `Task.async` /
  `Task.Supervisor.async(_nolink)` (which propagate `:"$callers"`). It is
  dropped automatically when that process exits.

  It will **not** fire for dispatches from a bare `spawn`, another GenServer's
  callback, an Oban job, `setup_all` (a different process from each test body),
  or `on_exit`. In those cases the handler is skipped silently — set the log
  level to `:debug` to see a line naming how many were skipped and why.

  For a durable, always-on handler, register via the `handlers:` option on
  `start_link/1` instead; those are exempt from owner scoping and always fire.
  """
  @spec subscribe(module(), atom(), (DomainEvent.t() -> :ok | {:error, term()}), keyword()) ::
          :ok
  def subscribe(context, event_type, handler_fn, opts \\ []) when is_atom(event_type) and is_function(handler_fn, 1) do
    GenServer.call(process_name(context), {:subscribe, event_type, handler_fn, opts, self()})
  end

  @doc """
  Dispatches a domain event to all registered handlers for its event type.

  Handlers are fetched from the registry and executed in the caller's process,
  sorted by priority (lower number first). Returns `:ok` when all handlers
  succeed, or `{:error, failures}` if any handler returns an error or crashes.
  """
  @spec dispatch(module(), dispatchable()) :: :ok | {:error, [term()]}
  def dispatch(context, event) when is_struct(event, DomainEvent) or is_struct(event, IntegrationEvent) do
    %{event_type: event_type} = event
    handlers = GenServer.call(process_name(context), {:get_handlers, event_type})

    handlers
    |> visible_to(caller_chain(), event_type)
    |> execute_handlers(event)
  end

  @doc """
  Dispatches a domain event and returns per-handler results with handler identity.

  Unlike `dispatch/2` which returns a flat `:ok` or `{:error, failures}`, this
  variant returns `{:ok, [{handler_identity, result}]}` so callers can determine
  which specific handlers succeeded or failed — needed for critical event routing
  where each handler's outcome must be tracked individually for retry logic.

  Handler identity is `{Module, :function}` for init-time registered handlers
  or `:anonymous` for runtime lambda subscriptions.
  """
  @spec dispatch_critical(module(), dispatchable()) ::
          {:ok, list({{module(), atom()} | :anonymous, :ok | {:error, term()}})}
  def dispatch_critical(context, event) when is_struct(event, DomainEvent) or is_struct(event, IntegrationEvent) do
    %{event_type: event_type} = event
    handlers = GenServer.call(process_name(context), {:get_handlers, event_type})

    {:ok,
     handlers
     |> visible_to(caller_chain(), event_type)
     |> execute_handlers_with_identity(event)}
  end

  @doc """
  Derives the process name for a context's DomainEventBus.
  """
  @spec process_name(module()) :: atom()
  def process_name(context) do
    Module.concat(context, DomainEventBus)
  end

  @impl true
  def init(%{context: context, handlers_spec: handlers_spec}) do
    Logger.info("DomainEventBus started for #{inspect(context)}")
    handlers = register_init_handlers(handlers_spec)

    {:ok, %__MODULE__{context: context, handlers: handlers}}
  end

  @impl true
  def handle_call({:subscribe, event_type, handler_fn, opts, owner}, _from, state) do
    # Monitoring the owner is what bounds the handler list: without it a subscription
    # lives for the life of the bus, so a long test run accumulates dead closures.
    Process.monitor(owner)

    # :anonymous identity signals to dispatch_critical/2 that this handler has no named origin for retry
    entry = {handler_fn, opts, :anonymous, owner}
    handlers = Map.update(state.handlers, event_type, [entry], &(&1 ++ [entry]))
    {:reply, :ok, %{state | handlers: handlers}}
  end

  @impl true
  def handle_call({:get_handlers, event_type}, _from, state) do
    entries = Map.get(state.handlers, event_type, [])
    {:reply, entries, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Enum.reject preserves the relative order of survivors, so sort_by_priority/1's
    # registration-order tie-break is unaffected.
    handlers =
      Map.new(state.handlers, fn {event_type, entries} ->
        {event_type, Enum.reject(entries, fn {_fn, _opts, _identity, owner} -> owner == pid end)}
      end)

    {:noreply, %{state | handlers: handlers}}
  end

  defp execute_handlers([], _event), do: :ok

  defp execute_handlers(entries, event) do
    failures =
      entries
      |> sort_by_priority()
      |> Enum.map(fn {{handler_fn, _opts, _identity, _owner}, _index} -> safe_call(handler_fn, event) end)
      |> Enum.filter(&match?({:error, _}, &1))

    if failures == [], do: :ok, else: {:error, failures}
  end

  defp execute_handlers_with_identity([], _event), do: []

  defp execute_handlers_with_identity(entries, event) do
    entries
    |> sort_by_priority()
    |> Enum.map(fn {{handler_fn, _opts, identity, _owner}, _index} ->
      {identity, safe_call(handler_fn, event)}
    end)
  end

  # Lower priority number runs first; stable sort preserves registration order for ties.
  defp sort_by_priority(entries) do
    entries
    |> Enum.with_index()
    |> Enum.sort_by(fn {{_fn, opts, _identity, _owner}, index} ->
      {Keyword.get(opts, :priority, @default_priority), index}
    end)
  end

  # Anonymous (runtime-subscribed) handlers are owned by the process that registered
  # them and fire only for dispatches from that process or a `Task` descendant of it
  # (`:"$callers"`). Boot-time handlers carry `:boot` and always fire, so production
  # behaviour is unchanged. Without this, a subscription on a globally-named bus hears
  # every concurrent async test's dispatch — see #1136.
  defp visible_to(entries, chain, event_type) do
    visible =
      Enum.filter(entries, fn
        {_handler_fn, _opts, _identity, :boot} -> true
        {_handler_fn, _opts, _identity, owner} -> owner in chain
      end)

    log_scoped_out(length(entries) - length(visible), event_type)

    visible
  end

  defp caller_chain, do: [self() | Process.get(:"$callers", [])]

  defp log_scoped_out(0, _event_type), do: :ok

  # A handler that silently never fires is this design's one bad failure mode.
  # Lazy, so it costs nothing unless someone turns debug on to investigate.
  defp log_scoped_out(count, event_type) do
    Logger.debug(fn ->
      "[DomainEventBus] #{count} anonymous handler(s) for #{inspect(event_type)} skipped — " <>
        "not owned by #{inspect(self())} nor any process in its :\"$callers\" chain"
    end)
  end

  defp safe_call(handler_fn, event) do
    case handler_fn.(event) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
      unexpected -> {:error, {:unexpected_return, unexpected}}
    end
  rescue
    error ->
      Logger.error("[DomainEventBus] handler crashed for #{event.event_type}",
        error: Exception.message(error),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      {:error, {:handler_crashed, error}}
  end

  defp register_init_handlers(specs) do
    Enum.reduce(specs, %{}, fn spec, acc ->
      {event_type, handler_fn, opts, identity} = normalize_handler_spec(spec)
      entry = {handler_fn, opts, identity, :boot}
      Map.update(acc, event_type, [entry], &(&1 ++ [entry]))
    end)
  end

  defp normalize_handler_spec({event_type, {module, function}}) do
    # Capture identity at registration so dispatch_critical/2 can report per-handler outcomes.
    {event_type, Function.capture(module, function, 1), [], {module, function}}
  end

  defp normalize_handler_spec({event_type, {module, function}, opts}) do
    {event_type, Function.capture(module, function, 1), opts, {module, function}}
  end
end
