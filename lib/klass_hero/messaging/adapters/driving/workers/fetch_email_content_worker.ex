defmodule KlassHero.Messaging.Adapters.Driving.Workers.FetchEmailContentWorker do
  @moduledoc """
  Fetches inbound email content from Resend's receiving API.

  Triggered after webhook stores email metadata. Updates email with
  body_html, body_text, headers, and sets content_status to fetched/failed.
  """

  use Oban.Worker, queue: :email, max_attempts: 3

  alias KlassHero.Shared.RateLimitedEmailWorker

  require Logger

  @email_content_fetcher Application.compile_env!(:klass_hero, [
                           :messaging,
                           :for_fetching_email_content
                         ])
  @inbound_email_repo Application.compile_env!(:klass_hero, [
                        :messaging,
                        :for_managing_inbound_emails
                      ])

  # Trigger: Resend API enforces rate limits
  # Why: default Oban backoff doesn't account for 429 responses — retries
  #      fire too soon and hit the limit again
  # Outcome: rate-limited jobs wait 30s+ before retry; other failures use 10s base
  @impl Oban.Worker
  def backoff(%Oban.Job{} = job), do: RateLimitedEmailWorker.backoff(job)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"email_id" => email_id, "resend_id" => resend_id}} = job) do
    case @email_content_fetcher.fetch_content(resend_id) do
      {:ok, content} ->
        attrs = %{
          body_html: content.html,
          body_text: content.text,
          headers: content.headers,
          content_status: "fetched"
        }

        case @inbound_email_repo.update_content(email_id, attrs) do
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
    if job.attempt >= job.max_attempts do
      case @inbound_email_repo.update_content(email_id, %{content_status: "failed"}) do
        {:ok, _} ->
          Logger.error("Marked email #{email_id} content as permanently failed")

        {:error, mark_reason} ->
          Logger.error("Failed to mark email #{email_id} as failed: #{inspect(mark_reason)}")
      end
    end
  end
end
