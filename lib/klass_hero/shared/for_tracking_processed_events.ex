defmodule KlassHero.Shared.ForTrackingProcessedEvents do
  @moduledoc """
  Port for tracking which event-handler pairs have been processed.

  Provides the persistence and durable retry infrastructure behind
  `CriticalEventDispatcher`. Implementations own the transactional
  atomicity guarantees — the domain service only sees `:ok` or
  `{:error, reason}`.
  """

  @doc """
  Atomically inserts a processed_events row and runs the handler.

  If the event-handler pair was already processed, skips the handler and
  returns `:ok`. If the handler succeeds, commits the row. If the handler
  fails or crashes, rolls back the row so retries remain possible.
  """
  @callback execute_atomically(
              event_id :: String.t(),
              handler_ref :: String.t(),
              handler_fn :: (-> :ok | :ignore | {:error, term()})
            ) :: :ok | {:error, term()}
end
