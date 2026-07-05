defmodule KlassHero.Messaging.EnforceRetentionPolicy do
  @moduledoc """
  Use case for enforcing data retention policy on messaging data.

  This use case:
  1. Collects S3 attachment URLs for expired conversations (before DB deletion)
  2. Deletes all messages from conversations that have exceeded their retention period
  3. Deletes the expired conversations themselves (cascade-deletes attachment records)
  4. Cleans up S3 files for the deleted attachments
  5. Publishes a retention_enforced event

  The S3 cleanup must happen AFTER the transaction succeeds, because the attachment
  records are cascade-deleted when messages are removed. We collect URLs before the
  transaction so we don't lose the file references.

  Typically run by a background worker (Oban) on a daily schedule after
  the archive worker has run.
  """

  alias KlassHero.Messaging.Domain.Events.MessagingEvents
  alias KlassHero.Repo
  alias KlassHero.Shared.DomainEventBus
  alias KlassHero.Shared.Storage

  require Logger

  @context KlassHero.Messaging

  @doc """
  Enforces retention policy by deleting expired messages and conversations.

  S3 attachment files are cleaned up after the transaction succeeds.

  ## Returns
  - `{:ok, %{messages_deleted: n, conversations_deleted: m}}` - Success
  - `{:error, reason}` - Failure
  """
  @spec execute() ::
          {:ok, %{messages_deleted: non_neg_integer(), conversations_deleted: non_neg_integer()}}
          | {:error, term()}
  def execute do
    now = DateTime.utc_now()

    Logger.info("Enforcing retention policy", timestamp: now)

    now
    |> run_retention_transaction()
    |> handle_result()
  end

  defp run_retention_transaction(now) do
    with {:ok, storage_paths} <- collect_attachment_storage_paths(now),
         {:ok, _} = result <- run_deletion_transaction(now) do
      cleanup_s3_files(storage_paths)
      result
    end
  end

  defp run_deletion_transaction(now) do
    Repo.transaction(fn ->
      with {:ok, msg_count, _conv_ids} <-
             KlassHero.Messaging.delete_messages_for_expired_conversations(now),
           {:ok, conv_count} <- KlassHero.Messaging.delete_expired_conversations(now) do
        %{messages_deleted: msg_count, conversations_deleted: conv_count}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp collect_attachment_storage_paths(now) do
    conversation_ids = KlassHero.Messaging.list_expired_conversation_ids(now)

    {:ok, paths} = KlassHero.Messaging.attachment_storage_paths_for_conversations(conversation_ids)
    Logger.debug("Collected S3 storage paths for retention cleanup", count: length(paths))
    {:ok, paths}
  end

  defp cleanup_s3_files([]), do: :ok

  defp cleanup_s3_files(storage_paths) do
    storage_paths
    |> Task.async_stream(
      fn path ->
        case Storage.delete(:public, path) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.warning("Failed to delete S3 file during retention cleanup",
              storage_path: path,
              reason: inspect(reason)
            )
        end
      end,
      timeout: :infinity
    )
    |> Enum.each(fn
      {:ok, _} ->
        :ok

      {:exit, reason} ->
        Logger.warning("S3 delete task crashed during retention cleanup",
          reason: inspect(reason)
        )
    end)
  end

  defp handle_result({:ok, result}) do
    publish_event(result.messages_deleted, result.conversations_deleted)

    Logger.info("Retention policy enforcement complete",
      messages_deleted: result.messages_deleted,
      conversations_deleted: result.conversations_deleted
    )

    {:ok, result}
  end

  defp handle_result({:error, reason} = error) do
    Logger.error("Retention policy enforcement failed",
      reason: inspect(reason)
    )

    error
  end

  defp publish_event(messages_deleted, conversations_deleted) do
    event = MessagingEvents.retention_enforced(messages_deleted, conversations_deleted)
    DomainEventBus.dispatch(@context, event)
    :ok
  end
end
