defmodule KlassHero.Messaging.ReceiveInboundEmail do
  @moduledoc """
  Use case for storing an inbound email received via webhook.

  Handles deduplication by resend_id — returns {:ok, :duplicate} for already-stored emails.
  """

  alias KlassHero.Messaging
  alias KlassHero.Messaging.Workers.FetchEmailContentWorker

  require Logger

  @spec execute(map()) :: {:ok, struct()} | {:ok, :duplicate} | {:error, term()}
  def execute(attrs) when is_map(attrs) do
    # Resend retries on non-2xx; deduplicate by resend_id.
    case Messaging.get_inbound_email_by_resend_id(attrs.resend_id) do
      {:ok, _existing} ->
        Logger.debug("Duplicate inbound email ignored: #{attrs.resend_id}")
        {:ok, :duplicate}

      {:error, :not_found} ->
        create_with_race_handling(attrs)
    end
  end

  # Concurrent deliveries may both pass the dedup check; unique_index catches the race.
  defp create_with_race_handling(attrs) do
    case Messaging.create_inbound_email(attrs) do
      {:ok, email} ->
        schedule_content_fetch(email)
        {:ok, email}

      {:error, %Ecto.Changeset{} = changeset} ->
        if unique_constraint_on?(changeset, :resend_id) do
          Logger.debug("Concurrent duplicate inbound email ignored: #{attrs.resend_id}")
          {:ok, :duplicate}
        else
          {:error, changeset}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Resend webhook omits body; fetch html/text/headers via API in a background job.
  defp schedule_content_fetch(email) do
    %{email_id: email.id, resend_id: email.resend_id}
    |> FetchEmailContentWorker.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} ->
        Logger.debug("Enqueued content fetch for email #{email.id}")

      {:error, reason} ->
        Logger.error("Failed to enqueue content fetch for #{email.id}: #{inspect(reason)}")
        Messaging.update_inbound_email_content(email.id, %{content_status: "failed"})
    end
  end

  defp unique_constraint_on?(%Ecto.Changeset{} = changeset, field) do
    Enum.any?(changeset.errors, fn
      {^field, {_, opts}} -> opts[:constraint] == :unique
      _ -> false
    end)
  end
end
