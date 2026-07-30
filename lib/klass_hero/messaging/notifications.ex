defmodule KlassHero.Messaging.Notifications do
  @moduledoc """
  Tells mounted LiveViews that a piece of messaging state changed.

  Replaces the `NotifyLiveViews` bus handler. A LiveView receives a tagged tuple
  naming what changed, never a `%DomainEvent{}`.

      {:message_sent, message_id}   # conversation topic — the open thread
      :conversations_changed        # user topic — that user's conversation list

  ## Who sends which

  The two are sent from different places on purpose, following the rule that
  *whoever writes the data a view reads is the one who notifies*.

  A conversation view reads the write model, so `send_message/1` notifies it
  directly and the message is available the moment the notification lands.

  The conversation *list* reads `conversation_summaries` — a projection the
  outbox job updates after the write commits. So `ConversationSummaries` sends
  `:conversations_changed` itself, once its rows are actually current. Notifying
  from the producer instead would race: the list would refetch and re-render the
  rows it already had.

  Best-effort, always `:ok` — a dropped refresh costs a stale view until the next
  render (ADR-0014).
  """

  @doc "The topic carrying one conversation's live traffic."
  @spec conversation_topic(String.t()) :: String.t()
  def conversation_topic(conversation_id), do: "conversation:#{conversation_id}"

  @doc "The topic carrying changes to one user's conversation list."
  @spec user_messages_topic(String.t()) :: String.t()
  def user_messages_topic(user_id), do: "user:#{user_id}:messages"

  @doc "Announces a new message to everyone with the conversation open."
  @spec message_sent(String.t(), String.t()) :: :ok
  def message_sent(conversation_id, message_id) do
    broadcast(conversation_topic(conversation_id), {:message_sent, message_id})
  end

  @doc """
  Tells one user their conversation list is out of date.

  Sent by `ConversationSummaries` after it writes, not by the producer — see the
  moduledoc.
  """
  @spec conversations_changed(String.t()) :: :ok
  def conversations_changed(user_id) do
    broadcast(user_messages_topic(user_id), :conversations_changed)
  end

  defp broadcast(topic, message) do
    Phoenix.PubSub.broadcast(KlassHero.PubSub, topic, message)
    :ok
  end
end
