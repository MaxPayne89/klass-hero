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
  Filter to the conversation whose principal pair is these two, in either order.
  """
  def between_principals(query \\ base(), user_id_1, user_id_2) do
    {a, b} = Conversation.principal_pair(user_id_1, user_id_2)

    where(query, [conversation: c], c.principal_a_id == ^a and c.principal_b_id == ^b)
  end

  @doc """
  Find the direct conversation between two specific users at a provider.

  Keyed on identity, not membership. Keying on "is a participant" cannot tell a
  provider-staff thread from a parent thread that staff member happens to sit in
  (`AddAssignedStaff` seats them), and hands an owner their staff member's thread
  with a parent — #1521.
  """
  def find_direct(provider_id, user_id_1, user_id_2) do
    base()
    |> by_provider(provider_id)
    |> by_type(:direct)
    |> active_only()
    |> between_principals(user_id_1, user_id_2)
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
  Total unread messages for a user, across every active, non-archived conversation.

  Feeds the nav badge. Shares its unread predicate with
  `unread_counts_by_conversation/2`, which feeds the per-card badges rendered directly
  beneath it — those two disagreeing is #1513, so they compose one definition rather
  than each restating it.
  """
  def total_unread_count(user_id) do
    from(p in Participant,
      as: :participant,
      join: c in Conversation,
      on: c.id == p.conversation_id,
      as: :conversation,
      where: p.user_id == ^user_id and is_nil(p.left_at) and is_nil(c.archived_at)
    )
    |> join_unread_messages(user_id)
    |> select([unread: m], count(m.id))
  end

  @doc """
  Unread counts for the given conversations, keyed by conversation id.

  The batched form of `total_unread_count/1`, for an inbox page. It deliberately does
  not re-filter `left_at` or `archived_at`: the ids come from a page query that already
  did, and a conversation with nothing unread simply has no row in the result.
  """
  def unread_counts_by_conversation(user_id, conversation_ids) do
    from(p in Participant,
      as: :participant,
      where: p.user_id == ^user_id and p.conversation_id in ^conversation_ids
    )
    |> join_unread_messages(user_id)
    |> group_by([participant: p], p.conversation_id)
    |> select([participant: p, unread: m], {p.conversation_id, count(m.id)})
  end

  # The one definition of "unread for this participant", joined onto a query that
  # already binds `:participant`.
  #
  # `m.sender_id != ^user_id` belongs to the set and is not redundant with the read
  # cursor. `SendMessage` stamps the sender's own `last_read_at` *after* the insert,
  # outside the transaction, and swallows the failure (`send_message.ex`) — so without
  # this the author's own message is counted whenever that write does not land.
  defp join_unread_messages(query, user_id) do
    join(query, :inner, [participant: p], m in Message,
      on:
        m.conversation_id == p.conversation_id and
          is_nil(m.deleted_at) and
          m.sender_id != ^user_id and
          (is_nil(p.last_read_at) or m.inserted_at > p.last_read_at),
      as: :unread
    )
  end
end
