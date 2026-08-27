defmodule KlassHero.Messaging.NewMessageEmailHandler do
  @moduledoc """
  Turns one `message_sent` event into one email job per participant who should
  hear about it.

  ## Why a consumer and not a call inside `SendMessage`

  `domain-architecture.md` says a same-context reaction is an ordinary function
  call made inside the producer's transaction, "so the write and its consequence
  commit together". That reasoning is about **database** writes. An email cannot
  be rolled back, so it must happen *after* commit, at-least-once, with retry —
  which is what the outbox is for. Sending inline would also drag a participants
  query, an Accounts query and up to N job inserts into a user-facing write, and
  would fail a person's message send because Resend was briefly unavailable.

  A handler, not a projection: `Shared.Projection.project/1` discards its
  callback's return and always answers `:ok`, which would swallow every dispatch
  failure. A `ForHandlingEvents` consumer propagates `{:error, reason}` back to
  `EventDeliveryWorker` for retry and compensation.

  ## Why the read-up filter queries the write side

  Consumers of one event run **sequentially**, and `ConversationSummaries` is
  also registered on `message_sent`. Filtering on its `unread_count` would mean
  reading a number that consumer may or may not have already incremented,
  depending on registry order — and if it ran first, every recipient would look
  "already unread" and no email would ever send. So the filter reads
  `conversation_participants.last_read_at` against `messages` instead, which no
  consumer mutates.
  """

  @behaviour KlassHero.Shared.ForHandlingEvents

  import Ecto.Query

  alias KlassHero.Accounts
  alias KlassHero.Messaging.Message
  alias KlassHero.Messaging.Participant
  alias KlassHero.Messaging.Workers.NewMessageEmailWorker
  alias KlassHero.Repo
  alias KlassHero.Shared.Tracing.Context

  @kind :new_message_email

  @impl true
  def subscribed_events, do: [:message_sent]

  @impl true
  # A system message is written by the platform, not typed by a person — today
  # only ReplyPrivatelyToBroadcast's "[broadcast:…]" context marker. Emailing on
  # it would notify the provider twice for one parent action, once for a line
  # the parent never wrote.
  def handle_event(%{event_type: :message_sent, payload: %{message_type: :system}}), do: :ok

  def handle_event(%{event_type: :message_sent, payload: payload}) do
    %{conversation_id: conversation_id, message_id: message_id, sender_id: sender_id} = payload

    conversation_id
    |> caught_up_user_ids(message_id)
    |> Enum.reject(&(&1 == sender_id))
    |> Accounts.notifiable_recipients(@kind)
    |> Map.keys()
    |> enqueue(conversation_id)
  end

  def handle_event(_event), do: :ignore

  # Active participants with nothing else outstanding in this conversation.
  # Someone already sitting on unread mail has been told; a second email says
  # nothing new and is what turns a busy thread into a mute.
  #
  # The `is_nil(last_read_at) or inserted_at > last_read_at` half is the same
  # "has this participant caught up" rule as `ConversationQueries.total_unread_count/1`
  # and `MessageQueries.count_unread/2` — three expressions of one rule, which is
  # why a change to any of them has to visit the others. See #1531.
  defp caught_up_user_ids(conversation_id, message_id) do
    from(p in Participant,
      where: p.conversation_id == ^conversation_id and is_nil(p.left_at),
      left_join: m in Message,
      on:
        m.conversation_id == p.conversation_id and
          m.id != ^message_id and
          is_nil(m.deleted_at) and
          (is_nil(p.last_read_at) or m.inserted_at > p.last_read_at),
      group_by: p.user_id,
      having: count(m.id) == 0,
      select: p.user_id
    )
    |> Repo.all()
  end

  defp enqueue([], _conversation_id), do: :ok

  defp enqueue(user_ids, conversation_id) do
    # One insert_all rather than a job-at-a-time insert: a program broadcast is
    # a single message to every enrolled family, so this list is routinely in
    # the hundreds. Stamping inserted_at from one clock keeps the batch ordered
    # together (see Enrollment.EnqueueInviteEmails, #1339).
    enqueued_at = DateTime.utc_now()

    jobs =
      Enum.map(user_ids, fn user_id ->
        %{"conversation_id" => conversation_id, "recipient_user_id" => user_id}
        |> Context.inject_into_args()
        |> NewMessageEmailWorker.new(inserted_at: enqueued_at)
      end)

    Oban.insert_all(jobs)

    :ok
  end
end
