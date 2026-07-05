defmodule KlassHero.Messaging.Adapters.Driving.Workers.RetentionPolicyWorker do
  @moduledoc """
  Oban worker that permanently deletes messages and conversations
  that have exceeded their retention period.

  This is a thin wrapper around the EnforceRetentionPolicy use case,
  scheduled to run daily at 4 AM via Oban cron configuration
  (after the archive worker has run at 3 AM).
  """

  use Oban.Worker, queue: :cleanup, max_attempts: 3

  alias KlassHero.Messaging.EnforceRetentionPolicy

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Starting retention policy worker")

    case EnforceRetentionPolicy.execute() do
      {:ok, result} ->
        Logger.info("Retention policy worker completed",
          messages_deleted: result.messages_deleted,
          conversations_deleted: result.conversations_deleted
        )

        :ok

      {:error, reason} ->
        Logger.error("Retention policy worker failed", reason: inspect(reason))
        {:error, reason}
    end
  end
end
