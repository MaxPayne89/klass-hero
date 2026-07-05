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

  @doc """
  Marks an event-handler pair as processed without running a handler.

  Used when a handler already succeeded synchronously. Idempotent — calling
  twice with the same args is safe. Must not raise on DB failure (logs and
  returns `:ok` to avoid disrupting callers).
  """
  @callback mark_processed(event_id :: String.t(), handler_ref :: String.t()) :: :ok

  @doc """
  Serializes an event and inserts a durable retry job.

  Used to enqueue Oban jobs for handlers that failed synchronous dispatch.
  The implementation owns serialization and job insertion.
  """
  @callback enqueue_durable_retry(
              event :: struct(),
              handler_ref :: String.t()
            ) :: :ok | {:error, term()}
end
