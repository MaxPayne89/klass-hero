defmodule KlassHero.Messaging.Queries.MessageQueries do
  @moduledoc """
  Composable Ecto query builders for messages.
  """

  import Ecto.Query

  alias KlassHero.Messaging.Attachment
  alias KlassHero.Messaging.Message

  @doc """
  Base query for messages.
  """
  def base do
    from(m in Message, as: :message)
  end

  @doc """
  Filter by message ID.
  """
  def by_id(query, id) do
    where(query, [message: m], m.id == ^id)
  end

  @doc """
  Filter by conversation.
  """
  def by_conversation(query, conversation_id) do
    where(query, [message: m], m.conversation_id == ^conversation_id)
  end

  @doc """
  Exclude deleted messages.
  """
  def not_deleted(query) do
    where(query, [message: m], is_nil(m.deleted_at))
  end

  @doc """
  Filter messages before a timestamp (for pagination).
  """
  def before(query, nil), do: query

  def before(query, timestamp) do
    where(query, [message: m], m.inserted_at < ^timestamp)
  end

  @doc """
  Filter messages after a timestamp (for real-time updates).
  """
  def after_timestamp(query, nil), do: query

  def after_timestamp(query, timestamp) do
    where(query, [message: m], m.inserted_at > ^timestamp)
  end

  @doc """
  Order by inserted_at descending (newest first).
  Secondary sort by id for deterministic ordering when timestamps match.
  """
  def order_by_newest(query) do
    order_by(query, [message: m], desc: m.inserted_at, desc: m.id)
  end

  @doc """
  Order by inserted_at ascending (oldest first).
  """
  def order_by_oldest(query) do
    order_by(query, [message: m], asc: m.inserted_at)
  end

  @doc """
  Get the latest message for a conversation.
  """
  def latest_for_conversation(conversation_id) do
    base()
    |> by_conversation(conversation_id)
    |> not_deleted()
    |> order_by_newest()
    |> limit(1)
  end

  @doc """
  Count unread messages after a timestamp.
  """
  def count_unread(conversation_id, nil) do
    base()
    |> by_conversation(conversation_id)
    |> not_deleted()
    |> select([message: m], count(m.id))
  end

  def count_unread(conversation_id, last_read_at) do
    base()
    |> by_conversation(conversation_id)
    |> not_deleted()
    |> after_timestamp(last_read_at)
    |> select([message: m], count(m.id))
  end

  @doc """
  Newest `inserted_at` per conversation, as `{conversation_id, inserted_at}` rows.

  Counts soft-deleted messages on purpose, so `not_deleted/1` is absent here where
  every other read applies it. This is the cursor someone is seated on when they join
  a conversation, and it must be **at or after every message already in it** so that
  nothing pre-existing can ever be badged as new. A soft-deleted newest message is
  still a message that was there; anchoring on the newest *visible* one would lower
  the cursor below it.

  That reasoning is now the only one. It used to be paired with a second — that the
  unread counters did not filter `deleted_at` either, so the anchor had to match them.
  They do filter it as of #1513, and this stands on its own.
  """
  def newest_inserted_at_by_conversation(conversation_ids) do
    conversation_ids
    |> grouped_by_conversation()
    |> select([message: m], {m.conversation_id, max(m.inserted_at)})
  end

  @doc """
  The newest message row per conversation — one row each, for a batch of ids.

  A subquery join rather than a `:messages` preload, which would load N×M rows.

  Returns a query. Callers execute and shape it — `ConversationSummaries` and
  `ListStaffConversations` both key the rows by `conversation_id`.

  Soft-deleted messages are excluded, on both sides of the join: this feeds a card
  **preview**, and a preview of a message the thread view refuses to render is #1513's
  bug wearing different clothes. `newest_inserted_at_by_conversation/1` deliberately
  does not filter them — it answers a different question. The two used to share one
  grouping that encoded "never filter"; they no longer can.
  """
  def latest_per_conversation(conversation_ids) do
    latest_times =
      conversation_ids
      |> grouped_by_conversation()
      |> not_deleted()
      |> select([message: m], %{conversation_id: m.conversation_id, max_at: max(m.inserted_at)})

    base()
    |> not_deleted()
    |> join(:inner, [message: m], lt in subquery(latest_times),
      on: m.conversation_id == lt.conversation_id and m.inserted_at == lt.max_at
    )
    |> select([message: m], %{
      id: m.id,
      conversation_id: m.conversation_id,
      content: m.content,
      sender_id: m.sender_id,
      inserted_at: m.inserted_at
    })
  end

  # Just the grouping. The `deleted_at` decision is each caller's — they disagree, and
  # both are right: a preview must skip soft-deleted messages, a seating cursor must
  # count them. Encoding either choice here is what coupled them.
  defp grouped_by_conversation(conversation_ids) do
    base()
    |> where([message: m], m.conversation_id in ^conversation_ids)
    |> group_by([message: m], m.conversation_id)
  end

  @doc """
  Of the given message ids, those carrying at least one attachment.
  """
  def message_ids_with_attachments(message_ids) do
    from(a in Attachment,
      where: a.message_id in ^message_ids,
      distinct: a.message_id,
      select: a.message_id
    )
  end

  @doc """
  Apply pagination with limit.
  """
  def paginate(query, opts) do
    limit = Keyword.get(opts, :limit, 50)
    before_ts = Keyword.get(opts, :before)
    after_ts = Keyword.get(opts, :after)

    query
    |> before(before_ts)
    |> after_timestamp(after_ts)
    |> limit(^(limit + 1))
  end

  @doc """
  Preload associations on the query.
  """
  def preload_assocs(query, []), do: query

  def preload_assocs(query, preloads) when is_list(preloads) do
    preload(query, ^preloads)
  end
end
