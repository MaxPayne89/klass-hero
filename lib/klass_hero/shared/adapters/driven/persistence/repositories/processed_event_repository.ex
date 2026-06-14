defmodule KlassHero.Shared.Adapters.Driven.Persistence.Repositories.ProcessedEventRepository do
  @moduledoc """
  Ecto/PostgreSQL implementation of `ForTrackingProcessedEvents`.

  Manages the `processed_events` table and provides the transactional
  atomicity guarantees for exactly-once event handler execution.
  """

  @behaviour KlassHero.Shared.Domain.Ports.ForTrackingProcessedEvents

  use KlassHero.Shared.Interaction

  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Events.CriticalEventSerializer
  alias KlassHero.Shared.Adapters.Driven.Persistence.Schemas.ProcessedEvent
  alias KlassHero.Shared.Adapters.Driven.Workers.CriticalEventWorker
  alias KlassHero.Shared.Tracing.Context

  require Logger

  @impl true
  def execute_atomically(event_id, handler_ref, handler_fn)
      when is_binary(event_id) and is_binary(handler_ref) and is_function(handler_fn, 0) do
    db_interaction operation: :execute_atomically, entity: "processed_event" do
      Repo.transaction(fn ->
        case insert_processed_event(event_id, handler_ref) do
          # Another delivery path already handled this pair — idempotent no-op.
          :already_processed ->
            :ok

          # Handler runs inside the transaction so rollback removes the row on failure.
          :inserted ->
            run_handler(handler_fn)
        end
      end)
      |> unwrap_transaction_result()
    end
  end

  @impl true
  def mark_processed(event_id, handler_ref) when is_binary(event_id) and is_binary(handler_ref) do
    db_interaction operation: :mark_processed, entity: "processed_event" do
      insert_processed_event(event_id, handler_ref)
      :ok
    end
  rescue
    error ->
      # Handler already succeeded — swallow DB failure and log; Oban may re-execute but idempotent handlers tolerate it.
      Logger.error(
        "Failed to mark event as processed: #{Exception.message(error)}",
        event_id: event_id,
        handler_ref: handler_ref,
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      :ok
  end

  @impl true
  def enqueue_durable_retry(event, handler_ref) when is_binary(handler_ref) do
    db_interaction operation: :enqueue_durable_retry, entity: "processed_event" do
      args =
        CriticalEventSerializer.serialize(event)
        |> Map.put("handler", handler_ref)
        |> Context.inject_into_args()

      case CriticalEventWorker.insert_job(args) do
        {:ok, _job} -> :ok
        {:error, _reason} = error -> error
      end
    end
  end

  defp insert_processed_event(event_id, handler_ref) do
    now = DateTime.utc_now()

    result =
      Repo.insert_all(
        ProcessedEvent,
        [%{event_id: event_id, handler_ref: handler_ref, processed_at: now}],
        on_conflict: :nothing
      )

    case result do
      {1, _} -> :inserted
      {0, _} -> :already_processed
    end
  end

  defp run_handler(handler_fn) do
    case handler_fn.() do
      :ok -> :ok
      :ignore -> :ok
      {:error, reason} -> Repo.rollback({:handler_failed, reason})
    end
  rescue
    error ->
      # Log before Repo.rollback, which loses the original stacktrace.
      Logger.error("Critical event handler crashed: #{Exception.message(error)}",
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      Repo.rollback({:handler_crashed, error})
  end

  defp unwrap_transaction_result({:ok, :ok}), do: :ok

  defp unwrap_transaction_result({:error, {:handler_failed, reason}}), do: {:error, reason}

  defp unwrap_transaction_result({:error, {:handler_crashed, error}}), do: {:error, {:handler_crashed, error}}

  defp unwrap_transaction_result({:error, reason}), do: {:error, reason}
end
