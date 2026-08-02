defmodule KlassHero.Messaging.Adapters.Driving.Workers.FetchEmailContentWorker do
  @moduledoc """
  Fetches inbound email content from Resend's receiving API.

  Triggered after webhook stores email metadata. Updates email with
  body_html, body_text, headers, and sets content_status to fetched/failed.
  """

  use KlassHero.Shared.RateLimitedEmailWorker, queue: :email, max_attempts: 3

  alias KlassHero.Messaging
  alias KlassHero.Messaging.Adapters.Driven.ResendEmailContentAdapter

  require Logger

  @impl true
  def execute(%Oban.Job{args: %{"email_id" => email_id, "resend_id" => resend_id}} = job) do
    case ResendEmailContentAdapter.fetch_content(resend_id) do
      {:ok, content} ->
        attrs = %{
          body_html: content.html,
          body_text: content.text,
          headers: content.headers,
          content_status: "fetched"
        }

        case Messaging.update_inbound_email_content(email_id, attrs) do
          {:ok, _email} ->
            Logger.info("Fetched content for inbound email #{email_id}")
            :ok

          {:error, :not_found} ->
            Logger.warning("Inbound email #{email_id} not found while storing content; discarding job")

            {:discard, :not_found}

          {:error, reason} ->
            Logger.error("Failed to store content for #{email_id}: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.warning("Content fetch failed for #{email_id} (attempt #{job.attempt}): #{inspect(reason)}")

        maybe_mark_permanently_failed(email_id, job)
        {:error, reason}
    end
  end

  defp maybe_mark_permanently_failed(email_id, job) do
    if TracedWorker.final_attempt?(job) do
      case Messaging.update_inbound_email_content(email_id, %{content_status: "failed"}) do
        {:ok, _} ->
          Logger.error("Marked email #{email_id} content as permanently failed")

        {:error, mark_reason} ->
          Logger.error("Failed to mark email #{email_id} as failed: #{inspect(mark_reason)}")
      end
    end
  end
end
