defmodule KlassHero.Messaging.Adapters.Driving.Workers.SendEmailReplyWorker do
  @moduledoc """
  Delivers an email reply via Swoosh/Resend.

  Fetches the EmailReply and associated InboundEmail, builds a Swoosh email
  with proper threading headers, delivers, and updates reply status.
  """

  use KlassHero.Shared.RateLimitedEmailWorker, queue: :email, max_attempts: 3
  use KlassHero.Shared.Interaction

  alias KlassHero.Messaging

  require Logger

  @from Application.compile_env!(:klass_hero, [:mailer_defaults, :from])

  @impl true
  def execute(%Oban.Job{args: %{"reply_id" => reply_id}} = job) do
    with {:ok, reply} <- Messaging.get_email_reply_by_id(reply_id),
         {:ok, email} <- Messaging.get_inbound_email_by_id(reply.inbound_email_id) do
      now = DateTime.utc_now()

      case deliver_reply(reply, email) do
        {:ok, %{id: resend_id}} ->
          mark_reply_sent(reply_id, %{resend_message_id: resend_id, sent_at: now})
          Logger.info("Delivered reply #{reply_id} to #{email.from_address}")
          :ok

        {:ok, _} ->
          mark_reply_sent(reply_id, %{sent_at: now})
          Logger.info("Delivered reply #{reply_id} to #{email.from_address}")
          :ok

        {:error, reason} ->
          Logger.error("Reply delivery failed for #{reply_id}: #{inspect(reason)}")
          mark_reply_failed_if_final(reply_id, job)
          {:error, reason}
      end
    else
      {:error, :not_found} ->
        Logger.error("Reply or email not found for reply #{reply_id}")
        mark_reply_failed_if_final(reply_id, job)
        {:discard, :not_found}
    end
  end

  defp deliver_reply(reply, email) do
    email_interaction operation: :send_reply do
      Swoosh.Email.new()
      |> Swoosh.Email.to(email.from_address)
      |> Swoosh.Email.from(@from)
      |> Swoosh.Email.subject("Re: #{email.subject}")
      |> Swoosh.Email.text_body(reply.body)
      |> maybe_add_threading_headers(email.message_id)
      |> KlassHero.Mailer.deliver()
    end
  end

  # Email already sent — do not raise/retry on status update failure (would cause duplicate sends).
  defp mark_reply_sent(reply_id, attrs) do
    case Messaging.update_email_reply_status(reply_id, "sent", attrs) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.critical("Reply #{reply_id} delivered but status update failed: #{inspect(reason)}")
    end
  end

  defp mark_reply_failed_if_final(reply_id, job) do
    if TracedWorker.final_attempt?(job) do
      case Messaging.update_email_reply_status(reply_id, "failed", %{}) do
        {:ok, _} ->
          Logger.error("Marked reply #{reply_id} as permanently failed")

        {:error, reason} ->
          Logger.error("Failed to mark reply #{reply_id} as failed: #{inspect(reason)}")
      end
    end
  end

  defp maybe_add_threading_headers(email, nil), do: email

  defp maybe_add_threading_headers(email, message_id) do
    email
    |> Swoosh.Email.header("In-Reply-To", message_id)
    |> Swoosh.Email.header("References", message_id)
  end
end
