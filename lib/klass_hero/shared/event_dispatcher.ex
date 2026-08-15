defmodule KlassHero.Shared.EventDispatcher do
  @moduledoc """
  Exactly-once dispatch for events.

  Owns the idempotency invariant: a given event-handler pair is processed at
  most once, however many times delivery is attempted. Since ADR-0014 there is
  one delivery path — `EventDeliveryWorker` — and Oban's at-least-once retry is
  what makes this gate load-bearing rather than defensive.

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
end
