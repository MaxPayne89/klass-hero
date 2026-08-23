defmodule KlassHero.Messaging.Queries.MessageQueries do
  @moduledoc """
  Composable Ecto query builders for messages.
  """

  import Ecto.Query

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
