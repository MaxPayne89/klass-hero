defmodule KlassHero.Participation do
  @moduledoc """
  Public API for the Participation bounded context.

  Covers session lifecycle, check-in/check-out, attendance, and session notes.
  Conventional Phoenix context: orchestration and persistence live here; the
  state machines live on the schema structs (`ProgramSession`,
  `ParticipationRecord`, `SessionNote`). Cross-context reads route through the
  owning contexts' public facades (`ProgramCatalog`, `Provider`) and the local
  `*Resolver` ACL adapters.

  State-changing operations open a `context_span`; the Ecto telemetry bridge
  nests per-query spans beneath it. Reads stay bare.
  """

  use KlassHero.Shared.Tracing

  import Ecto.Query

  alias KlassHero.Accounts.Scope
  alias KlassHero.Family
  alias KlassHero.Participation.Attendance
  alias KlassHero.Participation.ChildInfoResolver
  alias KlassHero.Participation.Events
  alias KlassHero.Participation.Notifications
  alias KlassHero.Participation.ParticipationRecord
  alias KlassHero.Participation.ProgramProviderResolver
  alias KlassHero.Participation.ProgramSession
  alias KlassHero.Participation.SessionAuthorization
  alias KlassHero.Participation.SessionNote
  alias KlassHero.Participation.SessionNoteQueries
  alias KlassHero.Participation.Sessions
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.EctoErrorHelpers
  alias KlassHero.Shared.Adapters.Driven.Persistence.RepositoryHelpers
  alias KlassHero.Shared.Outbox

  require Logger

  @context __MODULE__

  @note_update_fields [:content, :status, :rejection_reason, :submitted_at, :reviewed_at]

  # ============================================================================
  # Sessions
  # ============================================================================

  @doc "Creates a session on behalf of `scope`. See `Sessions.create_session/2`."
  defdelegate create_session(scope, params), to: Sessions

  @doc "Brings a program's generated sessions into agreement with its schedule."
  defdelegate sync_sessions_for_program(program_id), to: Sessions

  @doc "Starts a scheduled session on behalf of `scope`."
  defdelegate start_session(scope, session_id), to: Sessions

  @doc "Edits an existing session on behalf of `scope`."
  defdelegate update_session(scope, session_id, attrs), to: Sessions

  @doc "Lists sessions, optionally filtered by program or date."
  defdelegate list_sessions(params \\ %{}), to: Sessions

  @doc "Lists upcoming sessions across several programs from `from_date`."
  defdelegate list_upcoming_sessions_for_programs(program_ids, from_date), to: Sessions

  @doc "Lists sessions for the admin surface, with filters and resolved names."
  defdelegate list_admin_sessions(filters \\ %{}), to: Sessions

  @doc "Lists a provider's sessions, optionally for one date."
  defdelegate list_provider_sessions(provider_id, date \\ nil), to: Sessions

  @doc "Counts completed sessions across `program_ids`."
  defdelegate count_completed_sessions(program_ids), to: Sessions

  @doc "Retrieves a session by id. Returns `{:ok, session}` or `{:error, :not_found}`."
  defdelegate get_session(session_id), to: Sessions

  @doc "Batch sibling of `get_session/1`; unknown ids are omitted."
  defdelegate get_sessions(session_ids), to: Sessions

  @doc "Returns the list of valid session statuses."
  defdelegate session_statuses(), to: Sessions

  @doc """
  Completes an in-progress session on behalf of `scope`, marking all registered
  (not checked-in) children as absent.

  Authorized at this boundary rather than by the caller, for the reason ADR-0017
  gives for attendance: a guard that lives in one of four callers is not a guard.
  Completing a session marks every remaining registered child absent, and until
  #1373 the provider sessions list handed this function a client-supplied id with
  no check at all.

  Returns `{:ok, session}`, `{:error, :not_found}`, `{:error, :unauthorized}`,
  `{:error, :program_closed}`, or `{:error, :invalid_status_transition}`.
  """
  @spec complete_session(Scope.t(), String.t()) ::
          {:ok, ProgramSession.t()} | {:error, :not_found | SessionAuthorization.refusal() | :invalid_status_transition}
  def complete_session(%Scope{} = scope, session_id) when is_binary(session_id) do
    context_span entity: "session" do
      with {:ok, session} <- Sessions.get_session(session_id),
           {:ok, _role} <- SessionAuthorization.authorize_lifecycle(scope, session),
           {:ok, completed} <- ProgramSession.complete(session),
           {:ok, {persisted, events}} <- complete_session_with_events(completed) do
        Notifications.notify_all(events)
        {:ok, persisted}
      end
    end
  end

  @doc """
  Retrieves a session with its complete roster.

  Returns `{:ok, %{session: session, roster: roster}}` or `{:error, :not_found}`.
  """
  def get_session_with_roster(session_id) when is_binary(session_id) do
    with {:ok, session} <- Sessions.get_session(session_id) do
      records = Attendance.list_records_by_session(session_id)
      {child_info_map, notes_map, absence_reasons} = batch_resolve_roster(records)

      roster =
        Enum.map(records, fn record ->
          info = Map.get(child_info_map, record.child_id, unknown_child_info())
          notes = Map.get(notes_map, record.child_id, [])

          Map.merge(
            %{record: record},
            build_enrichment_fields(info, notes, Map.get(absence_reasons, record.id))
          )
        end)

      {:ok, %{session: session, roster: roster}}
    end
  end

  @doc """
  Like `get_session_with_roster/1` but enriches records with resolved child names for UI display.

  Returns `{:ok, session}` (with `participation_records` populated) or `{:error, :not_found}`.
  """
  def get_session_with_roster_enriched(session_id) when is_binary(session_id) do
    with {:ok, session} <- Sessions.get_session(session_id) do
      records = Attendance.list_records_by_session(session_id)
      {child_info_map, notes_map, absence_reasons} = batch_resolve_roster(records)

      enriched_records =
        Enum.map(records, fn record ->
          info = Map.get(child_info_map, record.child_id, unknown_child_info())
          notes = Map.get(notes_map, record.child_id, [])

          # Convert struct to plain map so presentation fields can be merged without struct enforcement.
          record
          |> Map.from_struct()
          |> Map.merge(build_enrichment_fields(info, notes, Map.get(absence_reasons, record.id)))
        end)

      enriched_session =
        session
        |> Map.from_struct()
        |> Map.put(:participation_records, enriched_records)
        |> Map.put(:program_name, Sessions.program_name(session.program_id))

      {:ok, enriched_session}
    end
  end

  @doc """
  Returns the provider-scoped participation topic — the single topic carrying all
  of a provider's participation traffic, session notes included. Provider and staff
  LiveViews subscribe to it; `Notifications` publishes to it. One builder, so the
  two sides can't drift.
  """
  @spec provider_topic(String.t()) :: String.t()
  defdelegate provider_topic(provider_id), to: Notifications

  @doc """
  Returns the child-scoped participation topic — the single topic carrying one
  child's attendance and session notes. Parent LiveViews subscribe to it per child;
  `Notifications` publishes to it (#1121).
  """
  @spec child_topic(String.t()) :: String.t()
  defdelegate child_topic(child_id), to: Notifications

  @doc """
  Returns the provider stats topic — the topic carrying `:session_stats_updated` to
  the provider overview, whose completed-session counter is a live count. The
  overview subscribes; `Notifications` publishes on `:session_completed`.
  """
  @spec stats_topic(String.t()) :: String.t()
  defdelegate stats_topic(provider_id), to: Notifications

  # ============================================================================
  # Attendance
  # ============================================================================

  @doc "Roster size and attendance tally for the given sessions, keyed by session id."
  defdelegate session_attendance_counts(session_ids), to: Attendance

  @doc "Counts an already-loaded roster into the same shape as `session_attendance_counts/1`."
  defdelegate attendance_from_roster(roster), to: Attendance

  @doc "Same tally as `attendance_from_roster/1`, for a bare list of records."
  defdelegate attendance_from_records(records), to: Attendance

  @doc "Seeds one session's roster from the program's active enrollments."
  defdelegate seed_session_roster(session_id, program_id), to: Attendance

  @doc "Seeds rosters for several sessions of one program."
  defdelegate seed_rosters_for_sessions(session_ids, program_id), to: Attendance

  @doc "Adds a late enrollee to the program's upcoming session rosters."
  defdelegate backfill_roster_for_enrollment(child_id, program_id), to: Attendance

  @doc "Checks a child in to a session, on behalf of `scope`."
  defdelegate record_check_in(scope, record_id, opts \\ []), to: Attendance

  @doc "Checks a child out of a session, on behalf of `scope`."
  defdelegate record_check_out(scope, record_id, opts \\ []), to: Attendance

  @doc "Marks a child absent by hand, on behalf of `scope`."
  defdelegate record_absence(scope, record_id, opts \\ []), to: Attendance

  @doc "Corrects a participation record's attendance data, on behalf of `scope`."
  defdelegate correct_attendance(scope, record_id, attrs), to: Attendance

  @doc "Retrieves a participation record by id."
  defdelegate get_participation_record(record_id), to: Attendance

  @doc "Retrieves participation history for one or more children."
  defdelegate get_participation_history(params), to: Attendance

  @doc "Returns the list of valid participation record statuses."
  defdelegate record_statuses(), to: Attendance

  # ============================================================================
  # Session notes
  # ============================================================================

  @doc """
  Submits a session note for a participation record, on behalf of `scope`.

  Required params: `participation_record_id`, `content` (max 1000 chars).

  Authorized against the record's session by the same rule as attendance
  (ADR-0017). The authoring provider is derived from the role that authorized the
  write — until #1329 this function took a `provider_id` and stamped it on the note
  without checking it against anything, so any caller could write a note about any
  child in any provider's name.

  Returns `{:ok, note}`, `{:error, :not_found}`, `{:error, :unauthorized}`,
  `{:error, :blank_content}`, `{:error, :invalid_record_status}`, or
  `{:error, :duplicate_note}`.
  """
  @spec submit_session_note(Scope.t(), map()) :: {:ok, SessionNote.t()} | {:error, atom()}
  def submit_session_note(%Scope{} = scope, %{participation_record_id: record_id, content: content}) do
    context_span entity: "session_note" do
      normalized_content = normalize_notes(content)

      with {:content, content} when content != nil <- {:content, normalized_content},
           {:ok, record} <- Attendance.get_participation_record(record_id),
           {:ok, role} <- Attendance.authorize_for_record(scope, record),
           {:ok, provider_id} <- authoring_provider_id(scope, role),
           true <- ParticipationRecord.allows_session_note?(record),
           {:ok, note} <- build_note(record, provider_id, content),
           {:ok, persisted} <- insert_note(note) do
        Notifications.notify(Events.session_note_submitted(persisted))

        {:ok, persisted}
      else
        {:content, nil} -> {:error, :blank_content}
        false -> {:error, :invalid_record_status}
        error -> error
      end
    end
  end

  @doc """
  Reviews a session note (approve or reject), on behalf of `scope`.

  Required params: `note_id`, `decision` (`:approve` or `:reject`). Optional: `reason`.
  The reviewing parent is the scope's, never the caller's to name.

  Returns `{:ok, note}`, `{:error, :not_found}`, `{:error, :unauthorized}`, or
  `{:error, :invalid_decision}`. The parent surface renders both refusals
  identically, so neither confirms a note id it was not given.
  """
  @spec review_session_note(Scope.t(), map()) :: {:ok, SessionNote.t()} | {:error, atom()}
  def review_session_note(%Scope{} = scope, %{note_id: note_id, decision: decision} = params) do
    context_span entity: "session_note" do
      reason = Map.get(params, :reason)

      with {:ok, note} <- fetch_note(note_id),
           :ok <- authorize_note_for_parent(scope, note),
           {:ok, reviewed} <- apply_review_decision(note, decision, reason),
           {:ok, persisted} <- update_note(reviewed) do
        Notifications.notify(review_event(persisted, decision))
        {:ok, persisted}
      end
    end
  end

  @doc """
  Revises a rejected session note with new content, on behalf of `scope`.

  Required params: `note_id`, `content`. The provider is the scope's; a caller
  cannot name the author of the note it is revising.
  """
  @spec revise_session_note(Scope.t(), map()) :: {:ok, SessionNote.t()} | {:error, atom()}
  def revise_session_note(%Scope{} = scope, %{note_id: note_id, content: content}) do
    context_span entity: "session_note" do
      normalized_content = normalize_notes(content)

      with {:content, content} when content != nil <- {:content, normalized_content},
           {:ok, note} <- fetch_note(note_id),
           :ok <- authorize_note_for_author(scope, note),
           {:ok, revised} <- SessionNote.revise(note, content),
           {:ok, persisted} <- update_note(revised) do
        Notifications.notify(Events.session_note_submitted(persisted))

        {:ok, persisted}
      else
        {:content, nil} -> {:error, :blank_content}
        error -> error
      end
    end
  end

  @doc """
  Anonymizes all session notes for a child during GDPR account deletion.

  Replaces note content with "[Removed - account deleted]", clears rejection
  reasons, and sets status to :rejected. Uses bulk update_all for efficiency.

  Returns `{:ok, count}` with the number of notes anonymized.
  """
  def anonymize_session_notes_for_child(child_id) when is_binary(child_id) do
    context_span entity: "session_note" do
      anonymize_notes_for_child(child_id, SessionNote.anonymized_attrs())
    end
  end

  @doc """
  Lists pending session notes for a parent awaiting review.

  Resolved through the parent's children rather than `session_notes.parent_id`,
  which no write path populates — see `parent_child_ids/1`.
  """
  def list_pending_session_notes(parent_id) when is_binary(parent_id) do
    {:ok, parent_id |> parent_child_ids() |> list_notes_pending_for_children()}
  end

  @doc "Gets approved session notes for a child."
  def get_approved_session_notes(child_id) when is_binary(child_id) do
    {:ok, list_notes_approved_by_child(child_id)}
  end

  @doc "Gets a session note by participation record and provider. Returns `{:ok, note}` or `{:error, :not_found}`."
  def get_session_note_by_record_and_provider(record_id, provider_id)
      when is_binary(record_id) and is_binary(provider_id) do
    fetch_note_by_record_and_provider(record_id, provider_id)
  end

  @doc """
  Lists session notes for multiple participation records by a single provider.

  Returns a flat list of notes. Use this instead of calling
  `get_session_note_by_record_and_provider/2` per record to avoid N+1 queries.
  """
  def list_session_notes_by_records_and_provider(record_ids, provider_id)
      when is_list(record_ids) and is_binary(provider_id) do
    list_notes_by_records_and_provider(record_ids, provider_id)
  end

  # Which provider a note is written in the name of. Derived from the role that
  # already authorized the write, so the two can never disagree; an admin holds no
  # provider identity and a Session Note is the Instructor's, so admin is refused
  # here even though `authorize_for_record/2` granted the write.
  defp authoring_provider_id(%Scope{provider: %{id: id}}, :provider), do: {:ok, id}
  defp authoring_provider_id(%Scope{staff_member: %{provider_id: id}}, :staff), do: {:ok, id}
  defp authoring_provider_id(%Scope{}, _role), do: {:error, :unauthorized}

  # A note is the parent's to review when it is about one of their children.
  # `session_notes.parent_id` is not consulted: no write path populates it (#1329).
  defp authorize_note_for_parent(%Scope{parent: %{id: parent_id}}, %SessionNote{child_id: child_id}) do
    if child_id in parent_child_ids(parent_id), do: :ok, else: {:error, :unauthorized}
  end

  defp authorize_note_for_parent(%Scope{}, %SessionNote{}), do: {:error, :unauthorized}

  # Revision is the author's alone — not the employing provider's, and not another
  # staff member's on the same session.
  defp authorize_note_for_author(%Scope{provider: %{id: id}}, %SessionNote{provider_id: id}), do: :ok

  defp authorize_note_for_author(%Scope{staff_member: %{provider_id: id}}, %SessionNote{provider_id: id}), do: :ok

  defp authorize_note_for_author(%Scope{}, %SessionNote{}), do: {:error, :unauthorized}

  defp build_note(record, provider_id, content) do
    SessionNote.new(%{
      id: Ecto.UUID.generate(),
      participation_record_id: record.id,
      child_id: record.child_id,
      # `parent_id` is deliberately not set. `participation_records.parent_id` is
      # NULL on every row the runtime seeds, so copying it here wrote NULL and made
      # a dead column look alive — which is what hid #1329. Ownership is asked of
      # Family, through the child.
      provider_id: provider_id,
      content: content
    })
  end

  defp apply_review_decision(note, :approve, _reason), do: SessionNote.approve(note)
  defp apply_review_decision(note, :reject, reason), do: SessionNote.reject(note, reason)
  defp apply_review_decision(_note, _decision, _reason), do: {:error, :invalid_decision}

  defp batch_resolve_roster(records) do
    child_ids = records |> Enum.map(& &1.child_id) |> Enum.uniq()
    child_info_map = ChildInfoResolver.resolve_children_info(child_ids)

    # Session notes are only visible when parent has consented — filter before fetching.
    consented_child_ids =
      child_info_map
      |> Enum.filter(fn {_id, info} -> info.has_consent? end)
      |> Enum.map(fn {id, _info} -> id end)

    notes_map =
      if consented_child_ids == [] do
        %{}
      else
        list_notes_approved_by_children(consented_child_ids)
      end

    {child_info_map, notes_map, Attendance.absence_reasons_for_records(records)}
  end

  defp build_enrichment_fields(child_info, notes, absence_reason) do
    %{
      child_name: "#{child_info.first_name} #{child_info.last_name}",
      child_first_name: child_info.first_name,
      child_last_name: child_info.last_name,
      allergies: child_info.allergies,
      support_needs: child_info.support_needs,
      emergency_contact: child_info.emergency_contact,
      session_notes: notes,
      absence_reason: absence_reason
    }
  end

  defp unknown_child_info do
    %{
      first_name: "Unknown",
      last_name: "Child",
      allergies: nil,
      support_needs: nil,
      emergency_contact: nil,
      has_consent?: false
    }
  end

  @doc false
  def normalize_notes(nil), do: nil

  def normalize_notes(notes) when is_binary(notes) do
    case String.trim(notes) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  # ============================================================================
  # Event publishing helpers
  # ============================================================================

  defp session_completed_event(session) do
    extra_payload = resolve_provider_details(session.program_id)
    Events.session_completed(session, extra_payload: extra_payload)
  end

  defp resolve_provider_details(program_id) do
    case ProgramProviderResolver.resolve_provider_details(program_id) do
      {:ok, details} ->
        details

      {:error, reason} ->
        Logger.warning("Could not resolve provider details for session_completed event",
          program_id: program_id,
          reason: inspect(reason)
        )

        %{provider_id: "00000000-0000-0000-0000-000000000000", program_title: "Unknown Program"}
    end
  end

  # The absences and the completion are one fact: a completed session whose
  # registered children were never marked absent is a half-finished write.
  defp complete_session_with_events(completed) do
    Outbox.transact_with_events(@context, fn ->
      with {:ok, persisted} <- Sessions.persist_lifecycle_update(completed),
           {:ok, absence_events} <- Attendance.mark_roster_absent_for_session(persisted) do
        {:ok, persisted, absence_events ++ [session_completed_event(persisted)]}
      end
    end)
  end

  defp review_event(note, :approve), do: Events.session_note_approved(note)
  defp review_event(note, :reject), do: Events.session_note_rejected(note)

  # ============================================================================
  # Persistence — session notes
  # ============================================================================

  defp insert_note(%SessionNote{} = note) do
    note
    |> Map.from_struct()
    |> SessionNote.create_changeset()
    |> Repo.insert()
    |> handle_note_insert()
  end

  defp update_note(%SessionNote{} = note) do
    case Repo.get(SessionNote, note.id) do
      nil ->
        {:error, :not_found}

      schema ->
        attrs = Map.take(note, @note_update_fields)

        schema
        |> SessionNote.update_changeset(attrs)
        |> Repo.update()
        |> handle_note_update()
    end
  end

  # Family owns the child→guardian relation, so it is asked rather than copied
  # (ADR-0015). A parent with no children yields an empty list, which every caller
  # below treats as "owns nothing" rather than "no filter".
  defp parent_child_ids(parent_id) do
    parent_id
    |> Family.get_child_ids_for_parent()
    |> MapSet.to_list()
  end

  defp list_notes_pending_for_children([]), do: []

  defp list_notes_pending_for_children(child_ids) do
    SessionNoteQueries.base()
    |> SessionNoteQueries.by_children(child_ids)
    |> SessionNoteQueries.pending()
    |> SessionNoteQueries.order_by_submitted_desc()
    |> Repo.all()
  end

  defp list_notes_approved_by_child(child_id) do
    SessionNoteQueries.base()
    |> SessionNoteQueries.by_child(child_id)
    |> SessionNoteQueries.approved()
    |> SessionNoteQueries.order_by_submitted_desc()
    |> Repo.all()
  end

  defp list_notes_approved_by_children(child_ids) do
    SessionNoteQueries.base()
    |> SessionNoteQueries.approved()
    |> where([note: n], n.child_id in ^child_ids)
    |> SessionNoteQueries.order_by_submitted_desc()
    |> Repo.all()
    |> Enum.group_by(& &1.child_id)
  end

  defp list_notes_by_records_and_provider(record_ids, provider_id) do
    SessionNoteQueries.base()
    |> SessionNoteQueries.by_participation_records(record_ids)
    |> SessionNoteQueries.by_provider(provider_id)
    |> Repo.all()
  end

  defp fetch_note(id) when is_binary(id) do
    RepositoryHelpers.get_schema_by_uuid(SessionNote, id)
  end

  defp fetch_note_by_record_and_provider(record_id, provider_id) do
    SessionNoteQueries.base()
    |> SessionNoteQueries.by_participation_record(record_id)
    |> SessionNoteQueries.by_provider(provider_id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      schema -> {:ok, schema}
    end
  end

  defp anonymize_notes_for_child(child_id, anonymized_attrs) when is_binary(child_id) and is_map(anonymized_attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # update_all bypasses Ecto.Enum casting — convert :status atom to string manually.
    set_fields =
      anonymized_attrs
      |> convert_note_enum_fields()
      |> Enum.to_list()
      |> Keyword.new()
      |> Keyword.put(:updated_at, now)

    {count, _} =
      SessionNote
      |> where([n], n.child_id == ^child_id)
      |> Repo.update_all(set: set_fields)

    {:ok, count}
  end

  defp handle_note_insert({:ok, schema}), do: {:ok, schema}

  defp handle_note_insert({:error, %Ecto.Changeset{errors: errors} = changeset}) do
    if EctoErrorHelpers.any_unique_constraint_violation?(errors) do
      {:error, :duplicate_note}
    else
      Logger.warning("[Participation] Session note validation failed on insert",
        errors: inspect(changeset.errors)
      )

      {:error, :validation_failed}
    end
  end

  defp handle_note_update({:ok, schema}), do: {:ok, schema}

  defp handle_note_update({:error, %Ecto.Changeset{} = changeset}) do
    Logger.warning("[Participation] Session note validation failed on update",
      errors: inspect(changeset.errors)
    )

    {:error, :validation_failed}
  end

  defp convert_note_enum_fields(attrs) do
    Map.update(attrs, :status, nil, fn
      value when is_atom(value) and not is_nil(value) -> to_string(value)
      value -> value
    end)
  end
end
