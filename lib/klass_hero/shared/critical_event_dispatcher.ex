defmodule KlassHero.Shared.CriticalEventDispatcher do
  @moduledoc """
  Exactly-once dispatch for critical events.

  Owns the idempotency invariant: a given event-handler pair is processed at
  most once, regardless of how many delivery paths attempt it. Both the PubSub
  real-time path and the Oban durable path funnel through this module.

  Delegates persistence and transactional atomicity to the
  `ForTrackingProcessedEvents` port — this domain service contains no
  infrastructure dependencies.
  """

  @processed_events Application.compile_env!(
                      :klass_hero,
                      [:shared, :for_tracking_processed_events]
                    )

  @doc """
  Derives the canonical handler reference string from a `{module, function}` tuple.

  Format: `"Elixir.Module.Name:function_name"`

  Used as the `handler_ref` column value in the `processed_events` table and in
  Oban job args. Both delivery paths must produce the same string for the same
  handler to ensure idempotency deduplication works.
  """
  @spec handler_ref({module(), atom()}) :: String.t()
  def handler_ref({module, function}) when is_atom(module) and is_atom(function) do
    # Atom.to_string/1 preserves the "Elixir." prefix that inspect/1 strips (>= 1.3),
    # required so PubSub and Oban paths produce identical handler_ref strings.
    "#{Atom.to_string(module)}:#{function}"
  end

  @doc """
  Reconstitutes a `{module, function}` tuple from a handler ref string.

  Inverse of `handler_ref/1`. Uses `String.to_existing_atom/1` — safe because
  handler modules are loaded at boot via the supervision tree.
  """
  @spec parse_handler_ref(String.t()) :: {module(), atom()}
  def parse_handler_ref(handler_ref_str) when is_binary(handler_ref_str) do
    case String.split(handler_ref_str, ":") do
      [module_str, function_str] ->
        {String.to_existing_atom(module_str), String.to_existing_atom(function_str)}

      _other ->
        raise ArgumentError,
              "Invalid handler_ref format: #{inspect(handler_ref_str)}. " <>
                "Expected \"Elixir.Module.Name:function_name\"."
    end
  end

  @doc """
  Executes a handler exactly once for a given event-handler pair.

  Delegates to the `ForTrackingProcessedEvents` port which atomically:
  1. Inserts a `processed_events` row (ON CONFLICT DO NOTHING)
  2. If inserted (not a duplicate), runs the handler function
  3. If handler succeeds, commits — row persists as proof of processing
  4. If handler fails or crashes, rolls back — row removed, allowing retry

  Returns `:ok` if the handler ran successfully, returned `:ignore`, or was already processed.
  Returns `{:error, reason}` if the handler failed (row is rolled back).
  """
  @spec execute(String.t(), String.t(), (-> :ok | :ignore | {:error, term()})) ::
          :ok | {:error, term()}
  def execute(event_id, handler_ref, handler_fn)
      when is_binary(event_id) and is_binary(handler_ref) and is_function(handler_fn, 0) do
    @processed_events.execute_atomically(event_id, handler_ref, handler_fn)
  end

  @doc """
  Marks an event-handler pair as processed without running a handler.

  Used by `EventDispatchHelper` when a critical domain event's handler already
  succeeded synchronously via `DomainEventBus`. Inserts the `processed_events`
  row so any subsequent Oban retry is a no-op.

  Idempotent — calling twice with the same args is safe.
  """
  @spec mark_processed(String.t(), String.t()) :: :ok
  def mark_processed(event_id, handler_ref) when is_binary(event_id) and is_binary(handler_ref) do
    @processed_events.mark_processed(event_id, handler_ref)
  end

  @doc """
  Enqueues a durable retry job for a failed handler.

  Derives the handler ref from the `{module, function}` tuple and delegates
  serialization + job insertion to the `ForTrackingProcessedEvents` port.
  """
  @spec enqueue_retry(struct(), {module(), atom()}) :: :ok | {:error, term()}
  def enqueue_retry(event, {module, function}) when is_atom(module) and is_atom(function) do
    ref = handler_ref({module, function})
    @processed_events.enqueue_durable_retry(event, ref)
  end
end
