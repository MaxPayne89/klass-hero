defmodule KlassHero.Messaging.ReplyToEmail do
  @moduledoc """
  Use case for replying to an inbound email.

  Persists the reply record with :sending status and enqueues
  an Oban job for async delivery via Swoosh/Resend.
  """

  alias KlassHero.Messaging
  alias KlassHero.Messaging.Workers.SendEmailReplyWorker

  require Logger

  @spec execute(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, struct()} | {:error, term()}
  def execute(email_id, reply_body, sent_by_id, _opts \\ []) do
    with {:ok, _email} <- Messaging.get_inbound_email_by_id(email_id),
         {:ok, reply} <-
           Messaging.create_email_reply(%{
             inbound_email_id: email_id,
             body: reply_body,
             sent_by_id: sent_by_id
           }),
         {:ok, _job} <- schedule_reply_delivery(reply.id) do
      Logger.info("Enqueued reply delivery #{reply.id} for email #{email_id}")
      {:ok, reply}
    else
      {:error, :not_found} = error ->
        error

      {:error, %Ecto.Changeset{}} = error ->
        error

      {:error, reason} ->
        Logger.error("Failed to schedule reply delivery: #{inspect(reason)}")
        {:error, :scheduling_failed}
    end
  end

  defp schedule_reply_delivery(reply_id) do
    %{reply_id: reply_id}
    |> SendEmailReplyWorker.new()
    |> Oban.insert()
  end
end
