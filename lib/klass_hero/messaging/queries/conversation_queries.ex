defmodule KlassHero.Messaging.Queries.ConversationQueries do
  @moduledoc """
  Composable Ecto query builders for conversations.
  """

  import Ecto.Query

  alias KlassHero.Messaging.Conversation
  alias KlassHero.Messaging.Message
  alias KlassHero.Messaging.Participant

  @doc """
  Base query for conversations.
  """
  def base do
    from(c in Conversation, as: :conversation)
  end

  @doc """
  Filter by conversation ID.
  """
  def by_id(query, id) do
    where(query, [conversation: c], c.id == ^id)
  end

  @doc """
  Filter by provider.
  """
  def by_provider(query, provider_id) do
    where(query, [conversation: c], c.provider_id == ^provider_id)
  end

  @doc """
  Filter by type.
  """
  def by_type(query, type) when is_atom(type) do
    by_type(query, to_string(type))
  end

  def by_type(query, type) when is_binary(type) do
    where(query, [conversation: c], c.type == ^type)
  end

  @doc """
  Filter by program.
  """
  def by_program(query, program_id) do
    where(query, [conversation: c], c.program_id == ^program_id)
  end

  @doc """
  Filter to only active (non-archived) conversations.
  """
  def active_only(query) do
    where(query, [conversation: c], is_nil(c.archived_at))
  end

  @doc """
  Filter to only archived conversations.
  """
  def archived_only(query) do
    where(query, [conversation: c], not is_nil(c.archived_at))
  end

  @doc """
  Filter conversations where user is an active participant.
  """
  def where_user_is_participant(query, user_id) do
    query
    |> join(:inner, [conversation: c], p in Participant,
      on: p.conversation_id == c.id and p.user_id == ^user_id and is_nil(p.left_at),
      as: :participant
    )
  end

  @doc """
  Filter conversations where user is NOT an *active* participant.

  Soft-left participations (where `left_at` is set) are treated as absent so
  the staff-reassignment flow can re-add a user who was previously removed.
  Without this, the LEFT JOIN would match the left row, set `p.id` to
  non-null, and the WHERE `is_nil(p.id)` would exclude the conversation
  forever — locking unassigned staff out of every program conversation
  they've ever left.
  """
  def where_user_is_not_participant(query, user_id) do
    query
    |> join(:left, [conversation: c], p in Participant,
      on:
        p.conversation_id == c.id and
          p.user_id == ^user_id and
          is_nil(p.left_at),
      as: :excluded_participant
    )
    |> where([excluded_participant: p], is_nil(p.id))
  end

  @doc """
  Find direct conversation between provider and user.
  """
  def find_direct(provider_id, user_id) do
    base()
    |> by_provider(provider_id)
    |> by_type(:direct)
    |> active_only()
    |> where_user_is_participant(user_id)
  end

  @doc """
  Filter conversations with retention period expired.
  """
  def retention_expired(query, before) do
    where(query, [conversation: c], c.retention_until < ^before)
  end

  @doc """
  Preload associations.
  """
  def preload_assocs(query, preloads) when is_list(preloads) do
    preload(query, ^preloads)
  end

  @doc """
  Filter to program_broadcast conversations where the associated program
  has ended before the cutoff date.

  Uses a two-step approach: first retrieves ended program IDs from
  the ProgramCatalog facade, then filters conversations by those IDs.
  Only returns active (non-archived) conversations.
  """
  def with_ended_program(query, cutoff_date) do
    ended_program_ids = KlassHero.ProgramCatalog.list_ended_program_ids(cutoff_date)

    query
    |> by_type(:program_broadcast)
    |> active_only()
    |> where([conversation: c], c.program_id in ^ended_program_ids)
  end

  @doc """
  Order newest first, by creation time.
  """
  def order_by_newest(query) do
    order_by(query, [conversation: c], desc: c.inserted_at, desc: c.id)
  end

  @doc """
  Apply seek pagination, newest-first.

  Fetches `limit + 1` rows so the caller can detect a next page without a second
  `COUNT` — the same trick `MessageQueries.paginate/2` and `list_inbound_emails/1`
  use. `:before` is an exclusive `inserted_at` cursor.
  """
  def paginate(query, opts) do
    limit = Keyword.get(opts, :limit, 25)

    query
    |> before(Keyword.get(opts, :before))
    |> limit(^(limit + 1))
  end

  defp before(query, nil), do: query

  defp before(query, timestamp) do
    where(query, [conversation: c], c.inserted_at < ^timestamp)
  end

  @doc """
  Select only conversation IDs for bulk operations.
  """
  def select_ids(query) do
    select(query, [conversation: c], c.id)
  end

  @doc """
  Query to get total unread message count across all conversations for a user.
  """
  def total_unread_count(user_id) do
    from(p in Participant,
      join: c in Conversation,
      on: c.id == p.conversation_id,
      join: m in Message,
      on:
        m.conversation_id == c.id and
          (is_nil(p.last_read_at) or m.inserted_at > p.last_read_at) and
          is_nil(m.deleted_at),
      where: p.user_id == ^user_id and is_nil(p.left_at) and is_nil(c.archived_at),
      select: count(m.id)
    )
  end
end
