defmodule KlassHero.Messaging.Adapters.Driven.Projections.ConversationSummaries do
  @moduledoc """
  Event-driven projection maintaining the `conversation_summaries` read table.

  This GenServer subscribes to Messaging integration events and keeps the
  denormalized `conversation_summaries` table in sync with the write model.
  On startup it bootstraps from the write tables (`conversations`,
  `conversation_participants`, `messages`, `users`), then incrementally
  applies changes as events arrive.

  ## Architecture

  Built on KlassHero.Shared.Projection + WithBootstrapRetry + WithDomainEvents.
  The read-side repository (`ConversationSummariesRepository`) queries the table
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
  - `:conversation_archived` — sets archived_at for all rows of a conversation
  - `:conversations_archived` — same as above but for multiple conversations
  - `:message_data_anonymized` — updates other_participant_name to "Deleted User"
    for rows where the anonymized user was the other participant
  """

  use KlassHero.Shared.Projection,
    topics: [
      "integration:messaging:conversation_created",
      "integration:messaging:message_sent",
      "integration:messaging:messages_read",
      "integration:messaging:conversation_archived",
      "integration:messaging:conversations_archived",
      "integration:messaging:message_data_anonymized",
      "integration:messaging:participant_added",
      "integration:messaging:participant_removed",
      "messaging:enrolled_children_changed"
    ]

  use KlassHero.Shared.Projection.WithBootstrapRetry
  use KlassHero.Shared.Projection.WithDomainEvents

  import Ecto.Query

  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.AttachmentSchema
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.ConversationSchema
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.ConversationSummarySchema
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.EnrolledChildrenSchema
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.MessageSchema
  alias KlassHero.Repo
  alias KlassHero.Shared.Domain.Events.IntegrationEvent
  alias KlassHero.Shared.Projection
  alias KlassHero.Shared.Projection.WithDomainEvents

  @user_resolver Application.compile_env!(:klass_hero, [:messaging, :for_resolving_users])
  @broadcast_token_regex ~r/\[broadcast:[^\]]+\]/

  # Behaviour callbacks ───────────────────────────────────────────────────────

  @impl Projection
  def bootstrap_impl, do: bootstrap_from_write_tables()

  @impl Projection
  def handle_event(:conversation_created, %IntegrationEvent{} = event) do
    Logger.debug("ConversationSummaries projecting conversation_created",
      conversation_id: event.entity_id,
      event_id: event.event_id
    )

    project_conversation_created(event)
  end

  def handle_event(:message_sent, %IntegrationEvent{} = event) do
    Logger.debug("ConversationSummaries projecting message_sent",
      conversation_id: event.entity_id,
      event_id: event.event_id
    )

    project_message_sent(event)
  end

  def handle_event(:messages_read, %IntegrationEvent{} = event) do
    Logger.debug("ConversationSummaries projecting messages_read",
      conversation_id: event.entity_id,
      event_id: event.event_id
    )

    project_messages_read(event)
  end

  def handle_event(:conversation_archived, %IntegrationEvent{} = event) do
    Logger.debug("ConversationSummaries projecting conversation_archived",
      conversation_id: event.entity_id,
      event_id: event.event_id
    )

    project_conversation_archived(event)
  end

  def handle_event(:conversations_archived, %IntegrationEvent{} = event) do
    Logger.debug("ConversationSummaries projecting conversations_archived",
      event_id: event.event_id
    )

    project_conversations_archived(event)
  end

  def handle_event(:message_data_anonymized, %IntegrationEvent{} = event) do
    Logger.debug("ConversationSummaries projecting message_data_anonymized",
      user_id: event.entity_id,
      event_id: event.event_id
    )

    project_message_data_anonymized(event)
  end

  def handle_event(:participant_added, %IntegrationEvent{} = event) do
    Logger.debug("ConversationSummaries projecting participant_added",
      conversation_id: event.entity_id,
      event_id: event.event_id
    )

    project_participant_added(event)
  end

  def handle_event(:participant_removed, %IntegrationEvent{} = event) do
    Logger.debug("ConversationSummaries projecting participant_removed",
      conversation_id: event.entity_id,
      event_id: event.event_id
    )

    project_participant_removed(event)
  end

  @impl WithDomainEvents
  def handle_domain_event(:enrolled_children_changed, event) do
    Logger.debug("ConversationSummaries projecting enrolled_children_changed",
      conversation_id: event.aggregate_id
    )

    project_enrolled_children_changed(event)
  end

  # Private Functions — Bootstrap

  # Trigger: bootstrap phase — read table may be empty or stale
  # Why: cold start recovery — populate read table from authoritative write tables
  # Outcome: conversation_summaries contains one row per (conversation, participant)
  defp bootstrap_from_write_tables do
    conversations =
      from(c in ConversationSchema, preload: [:participants])
      |> Repo.all()

    if conversations == [] do
      0
    else
      # Trigger: need user names to populate other_participant_name
      # Why: direct conversations show the other participant's display name
      # Outcome: user_id -> name lookup map built from users table
      all_user_ids =
        conversations
        |> Enum.flat_map(fn c -> Enum.map(c.participants, & &1.user_id) end)
        |> Enum.uniq()

      user_names = fetch_user_names(all_user_ids)

      # Trigger: need latest message per conversation without loading all messages
      # Why: preloading :messages loads N×M rows; this fetches N rows (one per conversation)
      # Outcome: efficient lookup map of conversation_id -> latest message fields
      conversation_ids = Enum.map(conversations, & &1.id)
      latest_messages = fetch_latest_messages(conversation_ids)

      # Trigger: need unread counts per (conversation, participant) without loading all messages
      # Why: counting in the DB is far cheaper than loading all messages into memory
      # Outcome: {conversation_id, user_id} -> unread_count lookup map
      unread_counts = fetch_unread_counts(conversations)

      # Trigger: need system note tokens per conversation for dedup tracking
      # Why: system messages with broadcast tokens must be pre-populated in the read table
      # Outcome: conversation_id -> %{token => iso8601_timestamp} lookup map
      system_notes = fetch_system_notes(conversation_ids)

      # Trigger: need to know which latest messages have attachments
      # Why: inbox preview shows an attachment indicator for messages with files
      # Outcome: MapSet of message_ids that have at least one attachment
      attachment_message_ids = fetch_attachment_message_ids(latest_messages)

      # Trigger: program_broadcast rows need a human label (program title)
      # Why: pre-existing nil for non-direct types surfaced as "Unknown" in the inbox (#892)
      # Outcome: program_id -> title map; nil for missing programs (rare race), UI falls back
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
        # Trigger: summaries may already exist from a previous run
        # Why: upsert avoids duplicate key errors while keeping data fresh
        # Outcome: all summaries projected, preserving original inserted_at on conflicts
        {count, _} =
          Repo.insert_all(ConversationSummarySchema, entries,
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
      resolve_other_participant_name(
        conversation.type,
        participant.user_id,
        active_participants,
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

  # Trigger: conversation_created event received
  # Why: each participant needs their own summary row with resolved display names
  # Outcome: one row per participant inserted (upsert for idempotency)
  defp project_conversation_created(event) do
    payload = event.payload
    conversation_id = payload.conversation_id
    participant_ids = Map.get(payload, :participant_ids, [])
    conversation_type = payload |> Map.get(:type, "direct") |> to_string()
    provider_id = Map.get(payload, :provider_id)
    program_id = Map.get(payload, :program_id)
    subject = Map.get(payload, :subject)
    participant_count = length(participant_ids)

    user_names = fetch_user_names(participant_ids)
    program_name = resolve_program_name(conversation_type, program_id)

    # Trigger: multiple participant rows must be inserted atomically
    # Why: a mid-loop crash without a transaction leaves partial rows,
    #      resulting in some participants having summaries and others not
    # Outcome: all-or-nothing insert — either every participant gets a row or none do
    Repo.transaction(fn ->
      Enum.each(participant_ids, fn user_id ->
        other_name =
          resolve_other_name_from_ids(
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
          unread_count: 0
        }

        %ConversationSummarySchema{}
        |> Ecto.Changeset.change(attrs)
        |> Repo.insert!(
          # Idempotency: on replay, refresh conversation metadata only.
          # Read-state fields (unread_count, last_read_at), message-state
          # fields (latest_message_*, has_attachments, system_notes,
          # enrolled_child_names) and archived_at MUST be preserved —
          # those are owned by other event handlers (:message_sent,
          # :messages_read, :conversation_archived).
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
               :updated_at
             ]},
          conflict_target: [:conversation_id, :user_id]
        )
      end)
    end)
  end

  # Trigger: participant_added event received
  # Why: one or more new participants joined a conversation; each needs a
  #      summary row back-filled from the current write-model state
  # Outcome: one row per new user_id upserted; meta refreshed on replay,
  #          read-state fields preserved
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
    from(c in ConversationSchema,
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

      Repo.insert_all(ConversationSummarySchema, entries,
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

  # Trigger: participant_removed event received
  # Why: removed users should not see the conversation in their inbox
  # Outcome: archived_at stamped on each affected row, preserving the first
  #          removal's timestamp on replay via COALESCE
  defp project_participant_removed(event) do
    payload = event.payload
    conversation_id = payload.conversation_id
    user_ids = Map.get(payload, :participant_user_ids, [])

    if user_ids == [] do
      :ok
    else
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      from(s in ConversationSummarySchema,
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

  # Trigger: message_sent event received
  # Why: all participants need updated latest_message fields;
  #      non-sender participants need incremented unread_count.
  #      Both updates wrapped in a transaction for atomicity — without it,
  #      a crash between the two updates leaves inconsistent read state.
  # Outcome: atomic bulk update for latest_message fields + selective unread increment
  defp project_message_sent(event) do
    payload = event.payload
    conversation_id = payload.conversation_id
    sender_id = payload.sender_id
    content = Map.get(payload, :content)
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    sent_at = Map.get(payload, :sent_at) || now
    has_attachments = (Map.get(payload, :attachments) || []) != []

    Repo.transaction(fn ->
      # Update latest_message fields for all participants of this conversation
      from(s in ConversationSummarySchema,
        where: s.conversation_id == ^conversation_id
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

      # Increment unread_count only for non-sender participants
      from(s in ConversationSummarySchema,
        where: s.conversation_id == ^conversation_id and s.user_id != ^sender_id
      )
      |> Repo.update_all(inc: [unread_count: 1])
    end)

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

  # Trigger: messages_read event received
  # Why: user has caught up on messages, unread_count should be zeroed
  # Outcome: single row updated with unread_count=0 and last_read_at
  defp project_messages_read(event) do
    payload = event.payload
    conversation_id = payload.conversation_id
    user_id = payload.user_id
    read_at = Map.get(payload, :read_at)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(s in ConversationSummarySchema,
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

  # Trigger: conversation_archived event received
  # Why: conversation is being archived, all summary rows must reflect this
  # Outcome: archived_at set on all rows for this conversation
  defp project_conversation_archived(event) do
    payload = event.payload
    conversation_id = payload.conversation_id
    archived_at = Map.get(payload, :archived_at)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(s in ConversationSummarySchema,
      where: s.conversation_id == ^conversation_id
    )
    |> Repo.update_all(
      set: [
        archived_at: archived_at,
        updated_at: now
      ]
    )
  end

  # Trigger: conversations_archived bulk event received
  # Why: multiple conversations archived at once (e.g. program ended)
  # Outcome: archived_at set on all rows for all affected conversations
  defp project_conversations_archived(event) do
    payload = event.payload
    conversation_ids = Map.get(payload, :conversation_ids, [])
    archived_at = Map.get(payload, :archived_at)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    if conversation_ids != [] do
      from(s in ConversationSummarySchema,
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

  # Trigger: message_data_anonymized event received (GDPR deletion)
  # Why: the anonymized user's name must no longer appear in other participants' summaries
  # Outcome: rows where the anonymized user is the "other participant" get name replaced
  defp project_message_data_anonymized(event) do
    anonymized_user_id = event.payload.user_id
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Trigger: find all conversations where the anonymized user is a participant
    # Why: we need to update the other_participant_name in rows belonging to
    #      the *other* participants (not the anonymized user themselves)
    # Outcome: "Deleted User" shown where the anonymized user was the counterpart
    conversation_ids =
      from(s in ConversationSummarySchema,
        where: s.user_id == ^anonymized_user_id,
        select: s.conversation_id
      )
      |> Repo.all()

    if conversation_ids != [] do
      from(s in ConversationSummarySchema,
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

  # Trigger: enrolled_children_changed domain event received
  # Why: update the enrolled_child_names for all participant rows of this conversation
  # Outcome: simple field update — projection stays dumb
  defp project_enrolled_children_changed(event) do
    conversation_id = event.payload.conversation_id
    child_names = Map.get(event.payload, :enrolled_child_names, [])
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(s in ConversationSummarySchema,
      where: s.conversation_id == ^conversation_id
    )
    |> Repo.update_all(
      set: [
        enrolled_child_names: child_names,
        updated_at: now
      ]
    )
  end

  # Private Functions — System Note Projection

  # Trigger: a message_sent event was received
  # Why: only system messages with broadcast tokens need tracking in the projection
  # Outcome: if a broadcast token is found, upsert into system_notes JSONB
  defp maybe_project_system_note(%{message_type: message_type, content: content} = payload)
       when message_type in [:system, "system"] do
    conversation_id = payload.conversation_id

    case Regex.run(@broadcast_token_regex, content || "") do
      [token] ->
        # Trigger: use event timestamp for deterministic, replay-safe values
        # Why: DateTime.utc_now() changes on each replay, causing unnecessary writes
        # Outcome: same event always produces the same JSONB value (truly idempotent)
        sent_at = Map.get(payload, :sent_at) || DateTime.utc_now()
        truncated_at = DateTime.truncate(sent_at, :second)
        token_json = %{token => DateTime.to_iso8601(truncated_at)}

        from(s in ConversationSummarySchema,
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

  # Trigger: bootstrap needs enrolled child names from the EnrolledChildren projection table
  # Why: direct conversations with a program_id should display child context — query across
  #      all participant user_ids (not just the current row's) so provider-side summary rows
  #      receive the same list as parent-side rows, matching the event-driven path's semantics
  # Outcome: list of child first names (deduped + sorted) or empty list
  defp resolve_enrolled_child_names(%{type: type, program_id: program_id}, participant_user_ids)
       when type in ["direct", :direct] and not is_nil(program_id) and participant_user_ids != [] do
    from(e in EnrolledChildrenSchema,
      where:
        e.parent_user_id in ^participant_user_ids and
          e.program_id == ^program_id and
          not is_nil(e.child_first_name),
      select: e.child_first_name,
      distinct: true,
      order_by: e.child_first_name
    )
    |> Repo.all()
  end

  defp resolve_enrolled_child_names(_, _), do: []

  # Private Functions — Helpers

  # Trigger: need to look up display names for a set of user IDs
  # Why: conversation summaries show the other participant's name
  # Outcome: map of user_id -> display name (name or email fallback)
  defp fetch_user_names(user_ids) when is_list(user_ids) and user_ids != [] do
    {:ok, names} = @user_resolver.get_display_names(user_ids)
    names
  end

  defp fetch_user_names(_), do: %{}

  # Trigger: bootstrap / participant_added need to display program titles on
  #          program_broadcast rows.
  # Why: cross-context read of programs table mirrors EnrolledChildren precedent —
  #      raw-string join sidesteps Boundary's compile-time isolation while
  #      preserving the projection-extend pattern (#892). The eventual cross-context
  #      port sweep is tracked by #685.
  # Outcome: map of program_id -> title for every broadcast conversation that
  #          carries a program_id; missing programs yield no entry, so callers
  #          read Map.get(..., id) which returns nil for the UI fallback.
  defp fetch_program_names_for_broadcasts(conversations) do
    program_ids =
      for c <- conversations,
          c.type == "program_broadcast",
          not is_nil(c.program_id),
          uniq: true,
          do: c.program_id

    fetch_program_names(program_ids)
  end

  defp fetch_program_names([]), do: %{}

  defp fetch_program_names(program_ids) do
    from(p in "programs",
      where: p.id in type(^program_ids, {:array, :binary_id}),
      select: {type(p.id, :binary_id), p.title}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp resolve_program_name("program_broadcast", program_id) when not is_nil(program_id) do
    [program_id] |> fetch_program_names() |> Map.get(program_id)
  end

  defp resolve_program_name(_type, _program_id), do: nil

  # Trigger: resolving other participant name for bootstrap (has ParticipantSchema structs)
  # Why: for direct conversations, each user sees the other's name
  # Outcome: display name of the other participant, or nil for broadcasts
  defp resolve_other_participant_name("direct", user_id, participants, user_names) do
    case Enum.find(participants, fn p -> p.user_id != user_id end) do
      nil -> nil
      other -> Map.get(user_names, other.user_id)
    end
  end

  defp resolve_other_participant_name(_type, _user_id, _participants, _user_names), do: nil

  # Trigger: resolving other participant name for events (has bare user_id list)
  # Why: conversation_created event carries participant_ids, not full structs
  # Outcome: display name of the other participant, or nil for broadcasts
  defp resolve_other_name_from_ids("direct", user_id, participant_ids, user_names) do
    case Enum.find(participant_ids, fn id -> id != user_id end) do
      nil -> nil
      other_id -> Map.get(user_names, other_id)
    end
  end

  defp resolve_other_name_from_ids(_type, _user_id, _participant_ids, _user_names), do: nil

  # Trigger: bootstrap needs latest message per conversation without loading all messages
  # Why: preloading :messages loads N×M rows; this fetches N rows (one per conversation)
  # Outcome: map of conversation_id -> %{id, content, sender_id, inserted_at}
  defp fetch_latest_messages(conversation_ids) when conversation_ids != [] do
    # Subquery finds the max inserted_at per conversation
    latest_times =
      from(m in MessageSchema,
        where: m.conversation_id in ^conversation_ids,
        group_by: m.conversation_id,
        select: %{conversation_id: m.conversation_id, max_at: max(m.inserted_at)}
      )

    from(m in MessageSchema,
      join: lt in subquery(latest_times),
      on: m.conversation_id == lt.conversation_id and m.inserted_at == lt.max_at,
      select: %{
        id: m.id,
        conversation_id: m.conversation_id,
        content: m.content,
        sender_id: m.sender_id,
        inserted_at: m.inserted_at
      }
    )
    |> Repo.all()
    |> Map.new(&{&1.conversation_id, &1})
  end

  defp fetch_latest_messages(_), do: %{}

  # Trigger: bootstrap needs to know which latest messages have file attachments
  # Why: inbox preview displays an attachment indicator when the latest message has files
  # Outcome: MapSet of message_ids that have at least one attachment row
  defp fetch_attachment_message_ids(latest_messages) when map_size(latest_messages) > 0 do
    message_ids = latest_messages |> Map.values() |> Enum.map(& &1.id)

    from(a in AttachmentSchema,
      where: a.message_id in ^message_ids,
      distinct: a.message_id,
      select: a.message_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp fetch_attachment_message_ids(_), do: MapSet.new()

  # Trigger: bootstrap needs to pre-populate system note tokens from existing system messages
  # Why: system messages with broadcast tokens must be tracked in the read table for dedup
  # Outcome: map of conversation_id -> %{token => iso8601_timestamp}
  defp fetch_system_notes(conversation_ids) when conversation_ids != [] do
    from(m in MessageSchema,
      where:
        m.conversation_id in ^conversation_ids and
          m.message_type == "system" and
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

  # Trigger: bootstrap needs unread counts per (conversation, participant) without loading messages
  # Why: counting in DB is far cheaper than loading all messages into memory
  # Outcome: map of {conversation_id, user_id} -> unread_count
  defp fetch_unread_counts(conversations) do
    # Build a list of {conversation_id, user_id, last_read_at} for each active participant
    participant_info =
      Enum.flat_map(conversations, fn conv ->
        conv.participants
        |> Enum.filter(&is_nil(&1.left_at))
        |> Enum.map(&{conv.id, &1.user_id, &1.last_read_at})
      end)

    # Group by last_read_at to batch queries efficiently
    # Most common case: nil (never read) or a few distinct timestamps
    {nil_readers, dated_readers} =
      Enum.split_with(participant_info, fn {_, _, lr} -> is_nil(lr) end)

    nil_counts = fetch_unread_counts_nil(nil_readers)
    dated_counts = fetch_unread_counts_dated(dated_readers)

    Map.merge(nil_counts, dated_counts)
  end

  # Trigger: participants who have never read — all messages from others are unread
  # Why: no last_read_at means every message from other senders counts
  # Outcome: count of messages per (conversation, user) where sender != user
  defp fetch_unread_counts_nil([]), do: %{}

  defp fetch_unread_counts_nil(readers) do
    # For nil last_read_at: count all messages from other senders
    Enum.reduce(readers, %{}, fn {conv_id, user_id, _}, acc ->
      count =
        from(m in MessageSchema,
          where: m.conversation_id == ^conv_id and m.sender_id != ^user_id,
          select: count(m.id)
        )
        |> Repo.one()

      Map.put(acc, {conv_id, user_id}, count)
    end)
  end

  # Trigger: participants with a last_read_at — only messages after that timestamp are unread
  # Why: messages before last_read_at have already been seen
  # Outcome: count of messages per (conversation, user) where sender != user and after last_read_at
  defp fetch_unread_counts_dated([]), do: %{}

  defp fetch_unread_counts_dated(readers) do
    Enum.reduce(readers, %{}, fn {conv_id, user_id, last_read_at}, acc ->
      count =
        from(m in MessageSchema,
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
