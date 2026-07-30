defmodule KlassHero.Shared.Adapters.Driven.Workers.CriticalEventWorker do
  @moduledoc """
  Generic Oban worker for durable delivery of critical events.

  Deserializes the event from job args, reconstitutes the handler function,
  and dispatches through `CriticalEventDispatcher` for exactly-once execution.

  Used in two modes:
  - **Domain events**: enqueued only when a handler fails during synchronous
    dispatch (retry on failure)
  - **Integration events**: always enqueued alongside PubSub for durable
    delivery (belt-and-suspenders, idempotency gate prevents double execution)
  """

  # Lifeline rescues an orphan only while `attempt < max_attempts` and discards it at the ceiling, so
  # this bound doubles as the window in which an orphaned event stays recoverable. 10 spans roughly
  # 4.5 hours under Oban's default backoff.
  use KlassHero.Shared.Tracing.TracedWorker,
    queue: :critical_events,
    max_attempts: 10

  alias KlassHero.Shared.Adapters.Driven.Events.CriticalEventSerializer
  alias KlassHero.Shared.CriticalEventDispatcher

  require Logger

  @doc """
  Inserts a critical event job and logs the outcome.

  Callers build the args map (serialized event + "handler" key); this function
  handles `Oban.insert/1` and consistent success/error logging.
  """
  @spec insert_job(map()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def insert_job(args) when is_map(args) do
    event_type = args["event_type"]
    handler = args["handler"]

    case Oban.insert(new(args)) do
      {:ok, _job} = ok ->
        Logger.debug("Enqueued critical event job: #{event_type} → #{handler}",
          event_id: args["event_id"],
          handler: handler
        )

        ok

      {:error, reason} = error ->
        Logger.error("Failed to enqueue critical event job: #{event_type} → #{handler}",
          event_id: args["event_id"],
          reason: inspect(reason)
        )

        error
    end
  end

  @impl true
  def execute(%Oban.Job{args: args, attempt: attempt, max_attempts: max_attempts}) do
    handler_ref_str = Map.fetch!(args, "handler")
    {module, function} = CriticalEventDispatcher.parse_handler_ref(handler_ref_str)
    event = CriticalEventSerializer.deserialize(args)

    result =
      CriticalEventDispatcher.execute(event.event_id, handler_ref_str, fn ->
        apply(module, function, [event])
      end)

    case result do
      :ok ->
        :ok

      # All retries exhausted — error level triggers ErrorTracker alerting.
      {:error, reason} when attempt >= max_attempts ->
        Logger.error(
          "Critical event permanently failed after #{max_attempts} attempts: " <>
            "event_type=#{args["event_type"]} handler=#{handler_ref_str}",
          event_id: args["event_id"],
          event_type: args["event_type"],
          handler: handler_ref_str,
          reason: inspect(reason),
          attempt: attempt,
          max_attempts: max_attempts
        )

        result

      # Warning level — retries remain; does not trigger ErrorTracker alerts.
      {:error, reason} ->
        Logger.warning(
          "Critical event handler failed (attempt #{attempt}/#{max_attempts}): " <>
            "event_type=#{args["event_type"]} handler=#{handler_ref_str}",
          event_id: args["event_id"],
          event_type: args["event_type"],
          handler: handler_ref_str,
          reason: inspect(reason),
          attempt: attempt,
          max_attempts: max_attempts
        )

        result
    end
  end
end
