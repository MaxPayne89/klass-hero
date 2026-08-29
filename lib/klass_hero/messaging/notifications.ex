defmodule KlassHero.Messaging.Notifications do
  @moduledoc """
  Tells mounted LiveViews that a piece of messaging state changed.

  Replaces the `NotifyLiveViews` bus handler. A LiveView receives a tagged tuple
  naming what changed, never an event struct.

      {:message_sent, message_id}   # conversation topic — the open thread
      :conversations_changed        # user topic — that user's conversation list

  ## Who sends which

  Both are sent by the producer, following the rule that *whoever writes the data
  a view reads is the one who notifies*.

  That was not always possible for `:conversations_changed`. The list used to read
  `conversation_summaries`, a projection an outbox job updated some time after the
  write committed, so the projection had to send this itself — notifying from the
  producer would have raced, and the list would have refetched the rows it already
  had. Retiring the projection (ADR-0023) inverted that: the list now reads the
  write model, so by the time the producer's transaction returns, a refetch sees
  the change.

  Sent from `SendMessage` (every active participant) and `CreateDirectConversation`
  (the two principals) — the two places the old projection notified from.

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

  Sent post-commit by whoever wrote the conversation or message — see the moduledoc.
  """
  @spec conversations_changed(String.t()) :: :ok
  def conversations_changed(user_id) do
    broadcast(user_messages_topic(user_id), :conversations_changed)
  end

  @doc """
  The same, for everyone a write touched.

  Both write paths reach for this shape — a message's active participants, a new
  thread's principals — so who to tell stays at the call site and how to tell them
  stays here, next to the topic scheme it depends on.
  """
  @spec conversations_changed_for([String.t()]) :: :ok
  def conversations_changed_for(user_ids) do
    Enum.each(user_ids, &conversations_changed/1)
  end

  defp broadcast(topic, message) do
    Phoenix.PubSub.broadcast(KlassHero.PubSub, topic, message)
    :ok
  end
end
