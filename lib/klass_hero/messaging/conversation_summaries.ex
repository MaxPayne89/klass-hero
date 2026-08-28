defmodule KlassHero.Messaging.ConversationSummaries do
  @moduledoc """
  Event-driven projection maintaining the `conversation_summaries` read table.

  This GenServer subscribes to Messaging integration events and keeps the
  denormalized `conversation_summaries` table in sync with the write model.
  On startup it bootstraps from the write tables (`conversations`,
  `conversation_participants`, `messages`, `users`), then incrementally
  applies changes as events arrive.

  ## Architecture

  Built on KlassHero.Shared.Projection + WithBootstrapRetry.
  The read side (the `KlassHero.Messaging` context) queries the table
  this projection writes.

  ## Startup Behavior

  On init, the GenServer:
  1. Subscribes to all relevant Messaging integration event topics
  2. Uses `handle_continue(:bootstrap)` to project all existing conversations
     into the read table

  ## Event Handling

  - `:conversation_created` — inserts one row per participant
  - `:message_sent` — updates latest_message fields, increments unread_count
    for non-sender participants
  - `:messages_read` — resets unread_count to 0, updates last_read_at
  - `:conversations_archived` — sets archived_at for all rows of the archived conversations
  - `:message_data_anonymized` — updates other_participant_name to "Deleted User"
    for rows where the anonymized user was the other participant
  """

  use KlassHero.Shared.Projection,
    topics: [
      "integration:messaging:conversation_created",
      "integration:messaging:message_sent",
      "integration:messaging:messages_read",
      "integration:messaging:conversations_archived",
      "integration:messaging:message_data_anonymized",
      "integration:messaging:participant_added",
      "integration:messaging:participant_removed",
      "integration:enrollment:enrollment_created",
      "integration:enrollment:enrollment_cancelled",
      "integration:family:child_created",
      "integration:family:child_updated"
    ]

  use KlassHero.Shared.Projection.WithBootstrapRetry
  use KlassHero.Shared.Tracing

  import Ecto.Query

  alias KlassHero.Accounts
  alias KlassHero.Messaging.Conversation
  alias KlassHero.Messaging.ConversationSummary
  alias KlassHero.Messaging.Message
  alias KlassHero.Messaging.Notifications
  alias KlassHero.Messaging.Queries.MessageQueries
  alias KlassHero.ProgramCatalog
  alias KlassHero.Repo
  alias KlassHero.Shared.Domain.Events.Event
  alias KlassHero.Shared.Projection

  @broadcast_token_regex ~r/\[broadcast:[^\]]+\]/

  @impl Projection
  def bootstrap_impl, do: bootstrap_from_write_tables()

  @impl Projection
  def handle_event(:conversation_created, %Event{} = event) do
    Logger.debug("ConversationSummaries projecting conversation_created",
      conversation_id: event.entity_id,
      event_id: event.event_id
    )

    project_conversation_created(event)
  end

  def handle_event(:message_sent, %Event{} = event) do
    Logger.debug("ConversationSummaries projecting message_sent",
      conversation_id: event.entity_id,
      event_id: event.event_id
    )

    project_message_sent(event)
  end

  def handle_event(:messages_read, %Event{} = event) do
    Logger.debug("ConversationSummaries projecting messages_read",
      conversation_id: event.entity_id,
      event_id: event.event_id
    )

    project_messages_read(event)
  end

  def handle_event(:conversations_archived, %Event{} = event) do
    Logger.debug("ConversationSummaries projecting conversations_archived",
      event_id: event.event_id
    )

    project_conversations_archived(event)
  end

  def handle_event(:message_data_anonymized, %Event{} = event) do
    Logger.debug("ConversationSummaries projecting message_data_anonymized",
      user_id: event.entity_id,
      event_id: event.event_id
    )

    project_message_data_anonymized(event)
  end

  def handle_event(:participant_added, %Event{} = event) do
    Logger.debug("ConversationSummaries projecting participant_added",
      conversation_id: event.entity_id,
      event_id: event.event_id
    )

    project_participant_added(event)
  end

  def handle_event(:participant_removed, %Event{} = event) do
    Logger.debug("ConversationSummaries projecting participant_removed",
      conversation_id: event.entity_id,
      event_id: event.event_id
    )

    project_participant_removed(event)
  end

  @impl Projection
  def handle_event(type, %Event{} = event)
      when type in [:enrollment_created, :enrollment_cancelled, :child_created, :child_updated] do
    refresh_enrolled_child_names(event.payload)
  end

  # Private Functions — Bootstrap

  defp bootstrap_from_write_tables do
    conversations =
      from(c in Conversation, preload: [:participants])
      |> Repo.all()

    if conversations == [] do
      0
    else
      all_user_ids =
        conversations
        |> Enum.flat_map(fn c -> Enum.map(c.participants, & &1.user_id) end)
        |> Enum.uniq()

      user_names = fetch_user_names(all_user_ids)

      conversation_ids = Enum.map(conversations, & &1.id)
      latest_messages = fetch_latest_messages(conversation_ids)

      unread_counts = fetch_unread_counts(conversations)
      system_notes = fetch_system_notes(conversation_ids)
      attachment_message_ids = fetch_attachment_message_ids(latest_messages)
      # program_broadcast rows need titles; nil on missing program (#892), UI falls back.
      program_names = fetch_program_names_for_broadcasts(conversations)

      globals = %{
        user_names: user_names,
        latest_messages: latest_messages,
        unread_counts: unread_counts,
        system_notes: system_notes,
        attachment_message_ids: attachment_message_ids,
        program_names: program_names,
        now: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      entries = Enum.flat_map(conversations, &build_conversation_entries(&1, globals))

      if entries == [] do
        0
      else
        {count, _} =
          Repo.insert_all(ConversationSummary, entries,
            on_conflict: {:replace_all_except, [:id, :inserted_at]},
            conflict_target: [:conversation_id, :user_id]
          )

        count
      end
    end
  end

  defp build_conversation_entries(conversation, %{} = globals) do
    active_participants = Enum.filter(conversation.participants, &is_nil(&1.left_at))

    context =
      globals
      |> Map.put(:active_participants, active_participants)
      |> Map.put(:latest_message, Map.get(globals.latest_messages, conversation.id))
      |> Map.put(:system_notes, Map.get(globals.system_notes, conversation.id, %{}))

    Enum.map(active_participants, fn participant ->
      build_summary_entry(conversation, participant, context)
    end)
  end

  defp build_summary_entry(conversation, participant, context) do
    %{
      active_participants: active_participants,
      user_names: user_names,
      latest_message: latest_message,
      unread_counts: unread_counts,
      system_notes: conv_system_notes,
      attachment_message_ids: attachment_message_ids,
      program_names: program_names,
      now: now
    } = context

    participant_count = length(active_participants)

    other_name =
      resolve_other_name(
        conversation.type,
        participant.user_id,
        Enum.map(active_participants, & &1.user_id),
        user_names
      )

    unread_count = Map.get(unread_counts, {conversation.id, participant.user_id}, 0)

    has_attachments =
      latest_message != nil and MapSet.member?(attachment_message_ids, latest_message.id)

    %{
      id: Ecto.UUID.generate(),
      conversation_id: conversation.id,
      user_id: participant.user_id,
      conversation_type: conversation.type,
      provider_id: conversation.provider_id,
      program_id: conversation.program_id,
      subject: conversation.subject,
      other_participant_name: other_name,
      program_name: Map.get(program_names, conversation.program_id),
      participant_count: participant_count,
      latest_message_content: latest_message && latest_message.content,
      latest_message_sender_id: latest_message && latest_message.sender_id,
      latest_message_at: latest_message && latest_message.inserted_at,
      has_attachments: has_attachments,
      unread_count: unread_count,
      last_read_at: participant.last_read_at,
      archived_at: conversation.archived_at,
      system_notes: conv_system_notes,
      enrolled_child_names: resolve_enrolled_child_names(conversation, Enum.map(active_participants, & &1.user_id)),
      inserted_at: now,
      updated_at: now
    }
  end

  # Private Functions — Event Projections

  defp project_conversation_created(event) do
    payload = event.payload
    conversation_id = payload.conversation_id
    participant_ids = Map.get(payload, :participant_ids, [])
    conversation_type = Map.get(payload, :type, :direct)
    provider_id = Map.get(payload, :provider_id)
    program_id = Map.get(payload, :program_id)
    subject = Map.get(payload, :subject)
    participant_count = length(participant_ids)

    user_names = fetch_user_names(participant_ids)
    program_name = resolve_program_name(conversation_type, program_id)

    # Computed here rather than left to a second handler. It used to be filled in
    # afterwards by the `EnrolledChildren` projection calling back into this module,
    # which is why it was excluded from the conflict list below.
    enrolled_child_names =
      resolve_enrolled_child_names(
        %{type: conversation_type, program_id: program_id},
        participant_ids
      )

    # Atomic insert: a mid-loop crash without a transaction would leave partial rows.
    Repo.transaction(fn ->
      Enum.each(participant_ids, fn user_id ->
        other_name =
          resolve_other_name(
            conversation_type,
            user_id,
            participant_ids,
            user_names
          )

        attrs = %{
          id: Ecto.UUID.generate(),
          conversation_id: conversation_id,
          user_id: user_id,
          conversation_type: conversation_type,
          provider_id: provider_id,
          program_id: program_id,
          subject: subject,
          other_participant_name: other_name,
          program_name: program_name,
          participant_count: participant_count,
          enrolled_child_names: enrolled_child_names,
          unread_count: 0
        }

        %ConversationSummary{}
        |> Ecto.Changeset.change(attrs)
        |> Repo.insert!(
          # Idempotency: on replay, refresh conversation metadata only.
          # Read-state fields (unread_count, last_read_at), message-state fields
          # (latest_message_*, has_attachments, system_notes) and archived_at MUST
          # be preserved — those are owned by other event handlers (:message_sent,
          # :messages_read, :conversations_archived).
          #
          # `enrolled_child_names` is replaced rather than preserved: this handler
          # now computes it, where it used to be written afterwards by the deleted
          # `EnrolledChildren` projection. Preserving a value this insert supplies
          # would pin the first roster a conversation ever saw.
          on_conflict:
            {:replace,
             [
               :conversation_type,
               :provider_id,
               :program_id,
               :subject,
               :other_participant_name,
               :program_name,
               :participant_count,
               :enrolled_child_names,
               :updated_at
             ]},
          conflict_target: [:conversation_id, :user_id]
        )
      end)
    end)

    # After the rows exist, so a list refetching on this sees them.
    Enum.each(participant_ids, &Notifications.conversations_changed/1)
  end

  defp project_participant_added(event) do
    payload = event.payload
    conversation_id = payload.conversation_id
    new_user_ids = Map.get(payload, :participant_user_ids, [])

    case load_conversation_with_participants(conversation_id) do
      nil ->
        Logger.warning(
          "ConversationSummaries: skipping participant_added — conversation missing",
          conversation_id: conversation_id,
          event_id: event.event_id
        )

        :ok

      conversation ->
        upsert_participant_summary_rows(conversation, new_user_ids)
    end
  end

  defp load_conversation_with_participants(conversation_id) do
    from(c in Conversation,
      where: c.id == ^conversation_id,
      preload: [:participants]
    )
    |> Repo.one()
  end

  defp upsert_participant_summary_rows(conversation, new_user_ids) do
    active_participants = Enum.filter(conversation.participants, &is_nil(&1.left_at))
    new_participants = Enum.filter(active_participants, &(&1.user_id in new_user_ids))

    if new_participants == [] do
      :ok
    else
      context = build_participant_context(conversation, active_participants)

      entries =
        Enum.map(new_participants, fn participant ->
          build_summary_entry(conversation, participant, context)
        end)

      Repo.insert_all(ConversationSummary, entries,
        # Idempotency: read-state and message-state preserved on replay.
        # `archived_at` IS in the replace list: the entry's value comes from
        # the conversation row (via build_summary_entry). For an active
        # conversation this is `nil`, which un-archives a row that was
        # previously archived by `:participant_removed` — exactly what
        # staff re-assignment needs. For an archived conversation, the
        # entry carries the conversation's archive timestamp, so the
        # archive state is preserved across re-events.
        on_conflict:
          {:replace,
           [
             :conversation_type,
             :provider_id,
             :program_id,
             :subject,
             :other_participant_name,
             :program_name,
             :participant_count,
             :archived_at,
             :updated_at
           ]},
        conflict_target: [:conversation_id, :user_id]
      )

      :ok
    end
  end

  defp build_participant_context(conversation, active_participants) do
    user_names = fetch_user_names(Enum.map(active_participants, & &1.user_id))
    latest_messages = fetch_latest_messages([conversation.id])
    unread_counts = fetch_unread_counts([conversation])
    system_notes = fetch_system_notes([conversation.id])
    attachment_message_ids = fetch_attachment_message_ids(latest_messages)
    program_names = fetch_program_names_for_broadcasts([conversation])
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      active_participants: active_participants,
      user_names: user_names,
      latest_message: Map.get(latest_messages, conversation.id),
      unread_counts: unread_counts,
      system_notes: Map.get(system_notes, conversation.id, %{}),
      attachment_message_ids: attachment_message_ids,
      program_names: program_names,
      now: now
    }
  end

  defp project_participant_removed(event) do
    payload = event.payload
    conversation_id = payload.conversation_id
    user_ids = Map.get(payload, :participant_user_ids, [])

    if user_ids == [] do
      :ok
    else
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      from(s in ConversationSummary,
        where: s.conversation_id == ^conversation_id and s.user_id in ^user_ids,
        update: [
          set: [
            # COALESCE preserves the first removal's timestamp on replay
            archived_at: fragment("COALESCE(?, ?)", s.archived_at, ^now),
            updated_at: ^now
          ]
        ]
      )
      |> Repo.update_all([])

      :ok
    end
  end

  # Wrapped in a transaction: a crash between the two updates would leave inconsistent read state.
  defp project_message_sent(event) do
    payload = event.payload
    conversation_id = payload.conversation_id
    sender_id = payload.sender_id
    content = Map.get(payload, :content)
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    sent_at = Map.get(payload, :sent_at) || now
    has_attachments = (Map.get(payload, :attachments) || []) != []

    {:ok, {_count, user_ids}} =
      Repo.transaction(fn ->
        result =
          from(s in ConversationSummary,
            where: s.conversation_id == ^conversation_id,
            select: s.user_id
          )
          |> Repo.update_all(
            set: [
              latest_message_content: content,
              latest_message_sender_id: sender_id,
              latest_message_at: sent_at,
              has_attachments: has_attachments,
              updated_at: now
            ]
          )

        from(s in ConversationSummary,
          where: s.conversation_id == ^conversation_id and s.user_id != ^sender_id
        )
        |> Repo.update_all(inc: [unread_count: 1])

        result
      end)

    # Exactly the users whose row changed — `select:` returns them, so no second
    # query and no chance of notifying someone this write did not touch.
    Enum.each(user_ids, &Notifications.conversations_changed/1)

    try do
      maybe_project_system_note(payload)
    rescue
      error ->
        Logger.error("Failed to project system note — will recover on next bootstrap",
          conversation_id: payload.conversation_id,
          error: Exception.message(error)
        )
    end
  end

  defp project_messages_read(event) do
    payload = event.payload
    conversation_id = payload.conversation_id
    user_id = payload.user_id
    read_at = Map.get(payload, :read_at)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(s in ConversationSummary,
      where: s.conversation_id == ^conversation_id and s.user_id == ^user_id
    )
    |> Repo.update_all(
      set: [
        unread_count: 0,
        last_read_at: read_at,
        updated_at: now
      ]
    )
  end

  defp project_conversations_archived(event) do
    # Destructured, not `Map.get`-ed: `project/1` discards this function's return, so a
    # defaulting read would write `archived_at: nil` and silently leave archived
    # conversations in every inbox — the bug #1216 fixed.
    %{conversation_ids: conversation_ids} = event.payload

    # Arrives as the %DateTime{} the producer sent: since #1311 the serializer records
    # typed payload values and rebuilds them, so DateTime arithmetic on this is safe.
    archived_at = legacy_archived_at(event)

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    if conversation_ids != [] do
      from(s in ConversationSummary,
        where: s.conversation_id in ^conversation_ids
      )
      |> Repo.update_all(
        set: [
          archived_at: archived_at,
          updated_at: now
        ]
      )
    end
  end

  # Producers before #1216 staged this event without `archived_at`. Such an event can only
  # be delivered in the window between that deploy and the queue draining, and its
  # `occurred_at` was stamped in the archiving transaction itself — close enough to the
  # value the row got, and far better than dropping the event into the dead-letter table
  # and leaving the conversation in every inbox. Delete this clause once no pre-#1216
  # event can still be queued.
  defp legacy_archived_at(%Event{payload: %{archived_at: archived_at}}), do: archived_at

  defp legacy_archived_at(%Event{} = event) do
    Logger.warning("conversations_archived carried no archived_at; falling back to occurred_at",
      event_id: event.event_id
    )

    event.occurred_at
  end

  defp project_message_data_anonymized(event) do
    anonymized_user_id = event.payload.user_id
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    conversation_ids =
      from(s in ConversationSummary,
        where: s.user_id == ^anonymized_user_id,
        select: s.conversation_id
      )
      |> Repo.all()

    if conversation_ids != [] do
      from(s in ConversationSummary,
        where:
          s.conversation_id in ^conversation_ids and
            s.user_id != ^anonymized_user_id
      )
      |> Repo.update_all(
        set: [
          other_participant_name: "Deleted User",
          updated_at: now
        ]
      )
    end
  end

  # Private Functions — System Note Projection

  defp maybe_project_system_note(%{message_type: message_type, content: content} = payload)
       when message_type == :system do
    conversation_id = payload.conversation_id

    case Regex.run(@broadcast_token_regex, content || "") do
      [token] ->
        # Use event timestamp rather than DateTime.utc_now() for replay idempotency.
        sent_at = Map.get(payload, :sent_at) || DateTime.utc_now()
        truncated_at = DateTime.truncate(sent_at, :second)
        token_json = %{token => DateTime.to_iso8601(truncated_at)}

        from(s in ConversationSummary,
          where: s.conversation_id == ^conversation_id,
          update: [
            set: [
              system_notes:
                fragment(
                  "coalesce(system_notes, '{}')::jsonb || ?::jsonb",
                  ^token_json
                ),
              updated_at: ^truncated_at
            ]
          ]
        )
        |> Repo.update_all([])

      _ ->
        :ok
    end
  end

  defp maybe_project_system_note(_payload), do: :ok

  # Query across all participant_user_ids (not just the current row's) so provider-side
  # summary rows receive the same child list as parent-side rows.
  #
  # Read live from Enrollment's and Family's write tables. This used to read a
  # `messaging_enrolled_children` mirror maintained by its own projection — a read
  # table whose only consumer was this function, kept in step by five event
  # subscriptions. The join it ran at bootstrap is the query below.
  defp resolve_enrolled_child_names(%{type: type, program_id: program_id}, participant_user_ids)
       when type in ["direct", :direct] and not is_nil(program_id) and participant_user_ids != [] do
    acl_span source: "messaging", target: "enrollment" do
      from(e in "enrollments",
        join: c in "children",
        on: c.id == e.child_id,
        join: pp in "parents",
        on: pp.id == e.parent_id,
        where:
          e.status in ["pending", "confirmed"] and
            e.program_id == type(^program_id, :binary_id) and
            pp.identity_id in type(^participant_user_ids, {:array, :binary_id}) and
            not is_nil(c.first_name),
        select: c.first_name,
        distinct: true,
        order_by: c.first_name
      )
      |> Repo.all()
    end
  end

  defp resolve_enrolled_child_names(_, _), do: []

  # `enrolled_child_names` is written when a conversation is created, so every
  # later change to the roster has to reach the row that already exists — a
  # sibling enrolled next term, a cancellation, a corrected spelling. Without
  # this the provider's thread keeps the roster it opened with until the next
  # deploy re-bootstraps it.
  defp refresh_enrolled_child_names(payload) do
    for {parent_user_id, program_id} <- affected_rosters(payload) do
      names = resolve_enrolled_child_names(%{type: :direct, program_id: program_id}, [parent_user_id])
      stamp_child_names(parent_user_id, program_id, names)
    end

    :ok
  end

  # Every (parent identity, program) the child is attached to, whatever the
  # enrollment's status: a cancellation still has to refresh the thread it just
  # left, and an active-only lookup would skip exactly that case.
  defp affected_rosters(%{child_id: child_id}) when is_binary(child_id) do
    acl_span source: "messaging", target: "enrollment" do
      from(e in "enrollments",
        join: pp in "parents",
        on: pp.id == e.parent_id,
        where: e.child_id == type(^child_id, :binary_id),
        select: {type(pp.identity_id, :binary_id), type(e.program_id, :binary_id)},
        distinct: true
      )
      |> Repo.all()
    end
  end

  defp affected_rosters(_), do: []

  defp stamp_child_names(parent_user_id, program_id, names) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    conversation_ids =
      from(s in ConversationSummary,
        where:
          s.user_id == ^parent_user_id and s.program_id == ^program_id and
            s.conversation_type == ^:direct,
        select: s.conversation_id,
        distinct: true
      )
      |> Repo.all()

    # Both sides of the thread carry the same roster, so the update is keyed on
    # the conversation rather than the parent's own row.
    from(s in ConversationSummary, where: s.conversation_id in ^conversation_ids)
    |> Repo.update_all(set: [enrolled_child_names: names, updated_at: now])
  end

  # Private Functions — Helpers

  defp fetch_user_names(user_ids) when is_list(user_ids) and user_ids != [] do
    Accounts.get_display_names(user_ids)
  end

  defp fetch_user_names(_), do: %{}

  defp fetch_program_names_for_broadcasts(conversations) do
    program_ids =
      for c <- conversations,
          c.type == :program_broadcast,
          not is_nil(c.program_id),
          uniq: true,
          do: c.program_id

    fetch_program_names(program_ids)
  end

  defp fetch_program_names([]), do: %{}

  defp fetch_program_names(program_ids) do
    ProgramCatalog.get_titles(program_ids)
  end

  defp resolve_program_name(:program_broadcast, program_id) when not is_nil(program_id) do
    [program_id] |> fetch_program_names() |> Map.get(program_id)
  end

  defp resolve_program_name(_type, _program_id), do: nil

  # Both the bootstrap and the event path land here. They used to be two functions
  # keyed on different spellings of the same value — `:direct` from `conversation.type`,
  # `"direct"` from the payload — which is the duplication #1327 removes.
  defp resolve_other_name(:direct, user_id, participant_ids, user_names) do
    case Enum.find(participant_ids, fn id -> id != user_id end) do
      nil -> nil
      other_id -> Map.get(user_names, other_id)
    end
  end

  defp resolve_other_name(_type, _user_id, _participant_ids, _user_names), do: nil

  # The SQL lives in MessageQueries so this projection and ListStaffConversations
  # cannot drift on what "latest message" means (#746).
  defp fetch_latest_messages(conversation_ids) when conversation_ids != [] do
    conversation_ids
    |> MessageQueries.latest_per_conversation()
    |> Repo.all()
    |> Map.new(&{&1.conversation_id, &1})
  end

  defp fetch_latest_messages(_), do: %{}

  defp fetch_attachment_message_ids(latest_messages) when map_size(latest_messages) > 0 do
    latest_messages
    |> Map.values()
    |> Enum.map(& &1.id)
    |> MessageQueries.message_ids_with_attachments()
    |> Repo.all()
    |> MapSet.new()
  end

  defp fetch_attachment_message_ids(_), do: MapSet.new()

  defp fetch_system_notes(conversation_ids) when conversation_ids != [] do
    from(m in Message,
      where:
        m.conversation_id in ^conversation_ids and
          m.message_type == :system and
          is_nil(m.deleted_at) and
          like(m.content, "%[broadcast:%"),
      select: %{
        conversation_id: m.conversation_id,
        content: m.content,
        inserted_at: m.inserted_at
      }
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn %{conversation_id: conv_id, content: content, inserted_at: at}, acc ->
      case Regex.run(@broadcast_token_regex, content || "") do
        [token] ->
          conv_notes = Map.get(acc, conv_id, %{})
          updated_notes = Map.put(conv_notes, token, DateTime.to_iso8601(at))
          Map.put(acc, conv_id, updated_notes)

        _ ->
          acc
      end
    end)
  end

  defp fetch_system_notes(_), do: %{}

  defp fetch_unread_counts(conversations) do
    participant_info =
      Enum.flat_map(conversations, fn conv ->
        conv.participants
        |> Enum.filter(&is_nil(&1.left_at))
        |> Enum.map(&{conv.id, &1.user_id, &1.last_read_at})
      end)

    {nil_readers, dated_readers} =
      Enum.split_with(participant_info, fn {_, _, lr} -> is_nil(lr) end)

    nil_counts = fetch_unread_counts_nil(nil_readers)
    dated_counts = fetch_unread_counts_dated(dated_readers)

    Map.merge(nil_counts, dated_counts)
  end

  defp fetch_unread_counts_nil([]), do: %{}

  defp fetch_unread_counts_nil(readers) do
    Enum.reduce(readers, %{}, fn {conv_id, user_id, _}, acc ->
      count =
        from(m in Message,
          where: m.conversation_id == ^conv_id and m.sender_id != ^user_id,
          select: count(m.id)
        )
        |> Repo.one()

      Map.put(acc, {conv_id, user_id}, count)
    end)
  end

  defp fetch_unread_counts_dated([]), do: %{}

  defp fetch_unread_counts_dated(readers) do
    Enum.reduce(readers, %{}, fn {conv_id, user_id, last_read_at}, acc ->
      count =
        from(m in Message,
          where:
            m.conversation_id == ^conv_id and
              m.sender_id != ^user_id and
              m.inserted_at > ^last_read_at,
          select: count(m.id)
        )
        |> Repo.one()

      Map.put(acc, {conv_id, user_id}, count)
    end)
  end
end
