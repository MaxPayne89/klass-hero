defmodule KlassHero.Messaging.Workers.NewMessageEmailWorker do
  @moduledoc """
  Delivers one "you have a new message" email.

  Args carry ids only. The address is fetched here rather than passed in for
  two reasons: an address in `oban_jobs.args` outlives the send by the Pruner's
  retention, and one changed between enqueue and delivery would send to the old
  mailbox.

  The preference is re-checked here too. `NewMessageEmailHandler` already
  filtered at enqueue — that keeps pointless jobs off a shared, rate-limited
  queue — but a broadcast's jobs can sit for a while, and someone who opts out
  in that window should not still receive the backlog.
  """

  use KlassHero.Shared.RateLimitedEmailWorker, queue: :email, max_attempts: 5

  alias KlassHero.Accounts
  alias KlassHero.Messaging.NewMessageEmailNotifier

  require Logger

  @kind :new_message_email

  @impl true
  def execute(%Oban.Job{args: %{"conversation_id" => conversation_id, "recipient_user_id" => user_id}})
      when is_binary(conversation_id) and is_binary(user_id) do
    case Accounts.notifiable_recipients([user_id], @kind) do
      %{^user_id => recipient} ->
        deliver(recipient, conversation_id, user_id)

      # Opted out after enqueue, or the account is gone. Neither is an error and
      # neither is fixable by retrying, so this is a completed job with no send.
      %{} ->
        :ok
    end
  end

  defp deliver(recipient, conversation_id, user_id) do
    case NewMessageEmailNotifier.send_new_message_notice(recipient, conversation_id) do
      {:ok, _email} ->
        :ok

      {:error, reason} ->
        Logger.error("New-message email failed",
          conversation_id: conversation_id,
          user_id: user_id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end
end
