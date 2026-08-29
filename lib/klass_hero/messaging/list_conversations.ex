defmodule KlassHero.Messaging.ListConversations do
  @moduledoc """
  A user's inbox page, read live from the write model.

  Replaces the `conversation_summaries` projection (ADR-0023). The shape is the one
  `KlassHero.Messaging.ListStaffConversations` already used for the staff inbox:
  page the conversations, then enrich the page with a fixed number of batched
  queries. Nothing runs per conversation.

  ## Cost per page

  Three SQL queries — the page itself, the unread counts, the attachment
  membership — plus two batched cross-context facade calls
  (`Accounts.get_display_names/1`, `ProgramCatalog.get_titles/1`) and one batched
  roster read. Flat in page size.

  The page query carries an `INNER LATERAL` onto each conversation's newest visible
  message. Inner rather than left on purpose: a conversation with no message must
  not appear, which is what the retired read table expressed as
  `not is_nil(latest_message_content) or has_attachments`.

  ## Ordering

  By the newest message, then by `conversation.id` — never by the message id. A
  conversation's newest-message identity changes as messages arrive, so a cursor
  tied to it would not be stable across page loads.

  The sort key lives in the lateral, so no single index serves the whole ordering.
  The nested loop is bounded by *one user's* conversation count, which is what the
  partial index on `conversation_participants(user_id) WHERE left_at IS NULL`
  narrows; growth in total conversations does not widen it.

  ## Soft-deleted messages

  Excluded from both the preview and the unread count. Those two must agree — a card
  previewing a message the badge refuses to count is the disagreement #1513 records
  in the other direction, where both counted them and the badge announced mail the
  reader could not open.
  """

  use KlassHero.Shared.Tracing

  import Ecto.Query

  alias KlassHero.Messaging.ConversationContext
  alias KlassHero.Messaging.InboxConversation
  alias KlassHero.Messaging.Message
  alias KlassHero.Messaging.Queries.ConversationQueries
  alias KlassHero.Messaging.Queries.MessageQueries
  alias KlassHero.ProgramCatalog
  alias KlassHero.Repo

  @default_limit 25

  @spec execute(String.t(), keyword()) :: {:ok, [InboxConversation.t()], boolean()}
  def execute(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)

    rows = Repo.all(page_query(user_id, limit + 1))
    page = Enum.take(rows, limit)

    {:ok, enrich(page, user_id), length(rows) > limit}
  end

  defp page_query(user_id, fetch) do
    ConversationQueries.base()
    |> ConversationQueries.where_user_is_participant(user_id)
    |> ConversationQueries.active_only()
    |> join(:inner_lateral, [conversation: c], m in subquery(latest_visible_message()),
      on: true,
      as: :latest
    )
    |> order_by([conversation: c, latest: m], desc: m.inserted_at, desc: c.id)
    |> limit(^fetch)
    |> preload([:participants])
    |> select([conversation: c, latest: m], %{conversation: c, message: m})
  end

  defp latest_visible_message do
    from(m in Message,
      where: m.conversation_id == parent_as(:conversation).id and is_nil(m.deleted_at),
      order_by: [desc: m.inserted_at, desc: m.id],
      limit: 1,
      select: %{
        id: m.id,
        content: m.content,
        sender_id: m.sender_id,
        inserted_at: m.inserted_at
      }
    )
  end

  defp enrich([], _user_id), do: []

  defp enrich(rows, user_id) do
    conversations = Enum.map(rows, & &1.conversation)

    context = %{
      unread: unread_counts(rows, user_id),
      attachment_ids: attachment_ids(rows),
      program_names: program_names(conversations),
      titling: ConversationContext.for_conversations(conversations, user_id)
    }

    Enum.map(rows, &build_row(&1, context))
  end

  # One grouped count for the whole page, sharing its unread predicate with the nav
  # badge rather than restating it — see `ConversationQueries`. Looping
  # `MessageQueries.count_unread/2` per row would be the N+1 this read exists to avoid.
  defp unread_counts(rows, user_id) do
    conversation_ids = Enum.map(rows, & &1.conversation.id)

    user_id
    |> ConversationQueries.unread_counts_by_conversation(conversation_ids)
    |> Repo.all()
    |> Map.new()
  end

  defp attachment_ids(rows) do
    rows
    |> Enum.map(& &1.message.id)
    |> MessageQueries.message_ids_with_attachments()
    |> Repo.all()
    |> MapSet.new()
  end

  # Skipped entirely on a page with no broadcast — `get_titles/1` has an empty clause.
  defp program_names(conversations) do
    for(%{type: :program_broadcast, program_id: id} <- conversations, not is_nil(id), uniq: true, do: id)
    |> ProgramCatalog.get_titles()
  end

  defp build_row(%{conversation: conversation, message: message}, context) do
    titling = Map.fetch!(context.titling, conversation.id)

    %InboxConversation{
      conversation_id: conversation.id,
      conversation_type: conversation.type,
      provider_id: conversation.provider_id,
      program_id: conversation.program_id,
      program_name: program_name(conversation, context.program_names),
      other_participant_name: titling.other_participant_name,
      enrolled_child_names: titling.enrolled_child_names,
      latest_message_content: message.content,
      latest_message_sender_id: message.sender_id,
      latest_message_at: message.inserted_at,
      has_attachments: MapSet.member?(context.attachment_ids, message.id),
      unread_count: Map.get(context.unread, conversation.id, 0)
    }
  end

  defp program_name(%{type: :program_broadcast, program_id: id}, names) when not is_nil(id) do
    Map.get(names, id)
  end

  defp program_name(_conversation, _names), do: nil
end
