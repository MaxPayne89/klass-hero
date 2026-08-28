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

  alias KlassHero.Accounts
  alias KlassHero.Messaging.Conversation
  alias KlassHero.Messaging.InboxConversation
  alias KlassHero.Messaging.Message
  alias KlassHero.Messaging.Participant
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
    from(c in Conversation, as: :conversation)
    |> join(:inner, [conversation: c], p in Participant,
      on: p.conversation_id == c.id and p.user_id == ^user_id and is_nil(p.left_at),
      as: :participant
    )
    |> join(:inner_lateral, [conversation: c], m in subquery(latest_visible_message()),
      on: true,
      as: :latest
    )
    |> where([conversation: c], is_nil(c.archived_at))
    |> order_by([conversation: c, latest: m], desc: m.inserted_at, desc: c.id)
    |> limit(^fetch)
    |> preload([:participants])
    |> select([conversation: c, participant: p, latest: m], %{
      conversation: c,
      last_read_at: p.last_read_at,
      message: m
    })
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
      user_id: user_id,
      unread: unread_counts(rows, user_id),
      attachment_ids: attachment_ids(rows),
      user_names: user_names(conversations),
      program_names: program_names(conversations),
      child_names: child_names(conversations)
    }

    Enum.map(rows, &build_row(&1, context))
  end

  # One grouped count for the whole page. Looping `MessageQueries.count_unread/2`
  # per row would be the N+1 this read exists to avoid.
  defp unread_counts(rows, user_id) do
    conversation_ids = Enum.map(rows, & &1.conversation.id)

    from(p in Participant,
      join: m in Message,
      on:
        m.conversation_id == p.conversation_id and is_nil(m.deleted_at) and
          m.sender_id != ^user_id and
          (is_nil(p.last_read_at) or m.inserted_at > p.last_read_at),
      where: p.user_id == ^user_id and p.conversation_id in ^conversation_ids,
      group_by: p.conversation_id,
      select: {p.conversation_id, count(m.id)}
    )
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

  defp user_names(conversations) do
    conversations
    |> Enum.flat_map(fn c -> Enum.map(c.participants, & &1.user_id) end)
    |> Enum.uniq()
    |> Accounts.get_display_names()
  end

  # Skipped entirely on a page with no broadcast — `get_titles/1` has an empty clause.
  defp program_names(conversations) do
    for(%{type: :program_broadcast, program_id: id} <- conversations, not is_nil(id), uniq: true, do: id)
    |> ProgramCatalog.get_titles()
  end

  # The children a direct thread is about, keyed by {program_id, parent identity}.
  # Status-agnostic on purpose beyond pending/confirmed: a cancelled enrollment stops
  # being part of the thread's subject, which is what the retired projection did.
  defp child_names(conversations) do
    program_ids =
      for(%{type: :direct, program_id: id} <- conversations, not is_nil(id), uniq: true, do: id)

    user_ids =
      for(
        %{type: :direct, program_id: id} = c <- conversations,
        not is_nil(id),
        participant <- c.participants,
        uniq: true,
        do: participant.user_id
      )

    fetch_child_names(program_ids, user_ids)
  end

  defp fetch_child_names([], _user_ids), do: %{}
  defp fetch_child_names(_program_ids, []), do: %{}

  defp fetch_child_names(program_ids, user_ids) do
    acl_span source: "messaging", target: "enrollment" do
      from(e in "enrollments",
        join: c in "children",
        on: c.id == e.child_id,
        join: pp in "parents",
        on: pp.id == e.parent_id,
        where:
          e.status in ["pending", "confirmed"] and
            e.program_id in type(^program_ids, {:array, :binary_id}) and
            pp.identity_id in type(^user_ids, {:array, :binary_id}) and
            not is_nil(c.first_name),
        select: {
          type(e.program_id, :binary_id),
          type(pp.identity_id, :binary_id),
          c.first_name
        },
        distinct: true
      )
      |> Repo.all()
      |> Enum.group_by(fn {program_id, user_id, _name} -> {program_id, user_id} end, &elem(&1, 2))
      |> Map.new(fn {key, names} -> {key, Enum.sort(names)} end)
    end
  end

  defp build_row(%{conversation: conversation, message: message}, context) do
    %InboxConversation{
      conversation_id: conversation.id,
      conversation_type: conversation.type,
      provider_id: conversation.provider_id,
      program_id: conversation.program_id,
      program_name: program_name(conversation, context.program_names),
      other_participant_name: other_participant_name(conversation, context),
      enrolled_child_names: enrolled_child_names(conversation, context),
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

  # Read off the principals rather than the participant list: a thread seats assigned
  # staff too, and a parent who has left stops being a participant while remaining who
  # the thread is with.
  defp other_participant_name(%{type: :direct} = conversation, context) do
    [conversation.principal_a_id, conversation.principal_b_id]
    |> Enum.reject(&(is_nil(&1) or &1 == context.user_id))
    |> case do
      [other | _] -> Map.get(context.user_names, other)
      [] -> fallback_participant_name(conversation, context)
    end
  end

  defp other_participant_name(_conversation, _context), do: nil

  # Threads predating the principal pair (#747) carry neither principal, so the only
  # answer left is the other active participant.
  defp fallback_participant_name(conversation, context) do
    conversation.participants
    |> Enum.filter(&(is_nil(&1.left_at) and &1.user_id != context.user_id))
    |> Enum.find_value(&Map.get(context.user_names, &1.user_id))
  end

  defp enrolled_child_names(%{type: :direct, program_id: program_id} = conversation, context)
       when not is_nil(program_id) do
    conversation.participants
    |> Enum.flat_map(&Map.get(context.child_names, {program_id, &1.user_id}, []))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp enrolled_child_names(_conversation, _context), do: []
end
