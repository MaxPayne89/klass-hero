defmodule KlassHero.Shared.Adapters.Driven.Persistence.Repositories.ProcessedEventRepository do
  @moduledoc """
  Ecto/PostgreSQL implementation of `ForTrackingProcessedEvents`.

  Manages the `processed_events` table and provides the transactional
  atomicity guarantees for exactly-once event handler execution.
  """

  @behaviour KlassHero.Shared.ForTrackingProcessedEvents

  use KlassHero.Shared.Interaction

  import Ecto.Query

  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.Schemas.ProcessedEvent

  require Logger

  @doc """
  Handler refs that have already processed `event_id`.

  Not part of `ForTrackingProcessedEvents`: that behaviour is about executing a
  handler atomically, and this is a plain read of what the table now knows. Its
  one caller is `EventDeliveryWorker.compensate/2`, working out which consumers a
  dead job never reached.
  """
  @spec processed_handler_refs(String.t()) :: [String.t()]
  def processed_handler_refs(event_id) when is_binary(event_id) do
    Repo.all(from(p in ProcessedEvent, where: p.event_id == ^event_id, select: p.handler_ref))
  end

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
