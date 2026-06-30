defmodule KlassHero.Participation do
  @moduledoc """
  Public API for the Participation bounded context.

  Covers session lifecycle, check-in/check-out, attendance, and behavioral notes.
  Conventional Phoenix context: orchestration and persistence live here; the
  state machines live on the schema structs (`ProgramSession`,
  `ParticipationRecord`, `BehavioralNote`). Cross-context reads route through ACL
  adapters (`SessionProgramAcl`, the `*Resolver`s).
  """

  use KlassHero.Shared.Interaction

  import Ecto.Query

  alias KlassHero.Participation.Adapters.Driven.ACL.ChildInfoResolver
  alias KlassHero.Participation.Adapters.Driven.ACL.EnrolledChildrenResolver
  alias KlassHero.Participation.Adapters.Driven.ACL.ProgramProviderResolver
  alias KlassHero.Participation.Adapters.Driven.ACL.SessionProgramAcl
  alias KlassHero.Participation.Adapters.Driven.Persistence.Queries.BehavioralNoteQueries
  alias KlassHero.Participation.Adapters.Driven.Persistence.Queries.ParticipationQueries
  alias KlassHero.Participation.BehavioralNote
  alias KlassHero.Participation.Domain.Events.ParticipationEvents
  alias KlassHero.Participation.ParticipationRecord
  alias KlassHero.Participation.ProgramSession
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.EctoErrorHelpers
  alias KlassHero.Shared.Adapters.Driven.Persistence.RepositoryHelpers
  alias KlassHero.Shared.DomainEventBus
  alias KlassHero.Shared.ErrorIds

  require Logger

  @context __MODULE__

  @record_update_fields [
    :status,
    :check_in_at,
    :check_in_notes,
    :check_in_by,
    :check_out_at,
    :check_out_notes,
    :check_out_by,
    :lock_version
  ]
  @note_update_fields [:content, :status, :rejection_reason, :submitted_at, :reviewed_at]

  # ============================================================================
  # Sessions
  # ============================================================================

  @doc """
  Creates a new program session.

  Required params: `program_id`, `session_date`, `start_time`, `end_time`.

  Returns `{:ok, session}`, `{:error, :invalid_time_range}`, or `{:error, :duplicate_session}`.
  """
  def create_session(params) when is_map(params) do
    session_attrs =
      params
      |> Map.put(:id, Ecto.UUID.generate())
      |> Map.put(:status, :scheduled)

    with {:ok, session} <- ProgramSession.new(session_attrs),
         {:ok, persisted} <- insert_session(session) do
      DomainEventBus.dispatch(@context, ParticipationEvents.session_created(persisted))
      {:ok, persisted}
    end
  end

  @doc """
  Starts a scheduled session.

  Returns `{:ok, session}`, `{:error, :not_found}`, or `{:error, :invalid_status_transition}`.
  """
  def start_session(session_id) when is_binary(session_id) do
    with {:ok, session} <- fetch_session(session_id),
         {:ok, started} <- ProgramSession.start(session),
         {:ok, persisted} <- update_session(started) do
      DomainEventBus.dispatch(@context, ParticipationEvents.session_started(persisted))
      {:ok, persisted}
    end
  end

  @doc """
  Completes an in-progress session, marking all registered (not checked-in) children as absent.

  Returns `{:ok, session}`, `{:error, :not_found}`, or `{:error, :invalid_status_transition}`.
  """
  def complete_session(session_id) when is_binary(session_id) do
    with {:ok, session} <- fetch_session(session_id),
         {:ok, completed} <- ProgramSession.complete(session),
         {:ok, persisted} <- update_session(completed),
         :ok <- mark_remaining_as_absent(persisted) do
      publish_session_completed(persisted)
      {:ok, persisted}
    end
  end

  @doc "Lists sessions, optionally filtered by `program_id` or `date`."
  def list_sessions(params \\ %{})

  def list_sessions(%{program_id: program_id}) when is_binary(program_id), do: list_sessions_by_program(program_id)

  def list_sessions(%{date: %Date{} = date}), do: list_sessions_today(date)
  def list_sessions(params) when is_map(params), do: list_sessions_today(Date.utc_today())

  @doc "Lists sessions with enriched data for the admin dashboard."
  def list_admin_sessions(filters \\ %{}) when is_map(filters) do
    # Default to today when no date filter is provided to avoid loading all sessions.
    filters =
      if not Map.has_key?(filters, :date) and
           not (Map.has_key?(filters, :date_from) and Map.has_key?(filters, :date_to)) do
        Map.put(filters, :date, Date.utc_today())
      else
        filters
      end

    SessionProgramAcl.list_admin_sessions(filters)
  end

  @doc "Lists sessions for a provider on a specific date (defaults to today)."
  def list_provider_sessions(provider_id, date \\ nil) when is_binary(provider_id) do
    date = date || Date.utc_today()
    {:ok, SessionProgramAcl.list_by_provider_and_date(provider_id, date)}
  end

  @doc """
  Retrieves a session with its complete roster.

  Returns `{:ok, %{session: session, roster: roster}}` or `{:error, :not_found}`.
  """
  def get_session_with_roster(session_id) when is_binary(session_id) do
    with {:ok, session} <- fetch_session(session_id) do
      records = list_records_by_session(session_id)
      {child_info_map, notes_map} = batch_resolve_roster(records)

      roster =
        Enum.map(records, fn record ->
          info = Map.get(child_info_map, record.child_id, unknown_child_info())
          notes = Map.get(notes_map, record.child_id, [])

          Map.merge(%{record: record}, build_enrichment_fields(info, notes))
        end)

      {:ok, %{session: session, roster: roster}}
    end
  end

  @doc """
  Like `get_session_with_roster/1` but enriches records with resolved child names for UI display.

  Returns `{:ok, session}` (with `participation_records` populated) or `{:error, :not_found}`.
  """
  def get_session_with_roster_enriched(session_id) when is_binary(session_id) do
    with {:ok, session} <- fetch_session(session_id) do
      records = list_records_by_session(session_id)
      {child_info_map, notes_map} = batch_resolve_roster(records)

      enriched_records =
        Enum.map(records, fn record ->
          info = Map.get(child_info_map, record.child_id, unknown_child_info())
          notes = Map.get(notes_map, record.child_id, [])

          # Convert struct to plain map so presentation fields can be merged without struct enforcement.
          record
          |> Map.from_struct()
          |> Map.merge(build_enrichment_fields(info, notes))
        end)

      enriched_session =
        session
        |> Map.from_struct()
        |> Map.put(:participation_records, enriched_records)
        |> Map.put(:program_name, SessionProgramAcl.get_program_name(session.program_id))

      {:ok, enriched_session}
    end
  end

  @doc "Returns the list of valid session statuses."
  def session_statuses, do: ProgramSession.valid_statuses()

  @doc """
  Seeds a session roster with the program's enrolled children. Best-effort: always returns `:ok`.

  Invoked by the `session_created` integration-event handler.
  """
  @spec seed_session_roster(String.t(), String.t()) :: :ok
  def seed_session_roster(session_id, program_id) when is_binary(session_id) and is_binary(program_id) do
    child_ids = EnrolledChildrenResolver.list_enrolled_child_ids(program_id)

    # max_capacity is not checked: capacity is an enrollment-time concern, not a roster gate.
    {:ok, count} = seed_records(session_id, child_ids)

    Logger.info(
      "[Participation] Seeded roster — enrolled=#{length(child_ids)} inserted=#{count} skipped=#{length(child_ids) - count}",
      session_id: session_id,
      program_id: program_id
    )

    safe_publish_roster_seeded(session_id, program_id, count)

    :ok
  rescue
    error ->
      Logger.error(
        "[Participation] Failed to seed roster: #{Exception.message(error)}",
        session_id: session_id,
        program_id: program_id,
        step: "acl_query_or_bulk_insert",
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      :ok
  end

  # ============================================================================
  # Attendance
  # ============================================================================

  @doc """
  Checks in a child to a session.

  Required params: `record_id`, `checked_in_by`. Optional: `notes`.

  Returns `{:ok, record}`, `{:error, :not_found}`, or `{:error, :invalid_status_transition}`.
  """
  def record_check_in(%{record_id: record_id, checked_in_by: checked_in_by} = params) do
    run_attendance_action(
      record_id,
      checked_in_by,
      Map.get(params, :notes),
      &ParticipationRecord.check_in/3,
      &ParticipationEvents.child_checked_in/2
    )
  end

  @doc """
  Checks out a child from a session.

  Required params: `record_id`, `checked_out_by`. Optional: `notes`.

  Returns `{:ok, record}`, `{:error, :not_found}`, or `{:error, :invalid_status_transition}`.
  """
  def record_check_out(%{record_id: record_id, checked_out_by: checked_out_by} = params) do
    run_attendance_action(
      record_id,
      checked_out_by,
      Map.get(params, :notes),
      &ParticipationRecord.check_out/3,
      &ParticipationEvents.child_checked_out/2
    )
  end

  @doc """
  Checks in multiple children at once.

  Required params: `record_ids`, `checked_in_by`. Optional: `notes`.

  Returns a map with `successful` (records) and `failed` (`{record_id, reason}` tuples).
  """
  def bulk_check_in(%{record_ids: record_ids, checked_in_by: checked_in_by} = params) do
    notes = Map.get(params, :notes)

    # Session resolved lazily from first successful record and reused — all records share the same session_id.
    {results, _session} =
      Enum.map_reduce(record_ids, nil, fn record_id, session ->
        case bulk_check_in_record(record_id, checked_in_by, notes, session) do
          {:ok, persisted, resolved_session} -> {{:ok, persisted}, resolved_session}
          {:error, _, _} = error -> {error, session}
        end
      end)

    results
    |> Enum.reduce(%{successful: [], failed: []}, &categorize_bulk_result/2)
    |> then(fn result ->
      %{successful: Enum.reverse(result.successful), failed: Enum.reverse(result.failed)}
    end)
  end

  @doc "Admin-corrects a participation record's attendance data."
  def correct_attendance(%{record_id: record_id} = params) do
    actor_role = Map.get(params, :actor_role, :admin)

    with :ok <- validate_correction_reason(actor_role, params),
         {:ok, record} <- fetch_record(record_id),
         correction_attrs = build_correction_attrs(actor_role, record, params),
         {:ok, corrected} <- ParticipationRecord.admin_correct(record, correction_attrs) do
      update_record(corrected)
    end
  end

  @doc "Retrieves a participation record by ID. Returns `{:ok, record}` or `{:error, :not_found}`."
  def get_participation_record(record_id) when is_binary(record_id) do
    fetch_record(record_id)
  end

  @doc """
  Retrieves participation history for one or more children.

  Accepts `child_id` or `child_ids`, with optional `start_date`/`end_date`.
  Returns `{:ok, records}` ordered by date descending.
  """
  def get_participation_history(%{child_ids: child_ids} = params) when is_list(child_ids) do
    start_date = Map.get(params, :start_date)
    end_date = Map.get(params, :end_date)

    records =
      if start_date && end_date do
        list_records_by_children_and_date_range(child_ids, start_date, end_date)
      else
        list_records_by_children(child_ids)
      end

    {:ok, records}
  end

  def get_participation_history(%{child_id: child_id} = params) do
    start_date = Map.get(params, :start_date)
    end_date = Map.get(params, :end_date)

    records =
      if start_date && end_date do
        list_records_by_child_and_date_range(child_id, start_date, end_date)
      else
        list_records_by_child(child_id)
      end

    {:ok, records}
  end

  @doc "Returns the list of valid participation record statuses."
  def record_statuses, do: ParticipationRecord.valid_statuses()

  # ============================================================================
  # Behavioral notes
  # ============================================================================

  @doc """
  Submits a behavioral note for a participation record.

  Required params: `participation_record_id`, `provider_id`, `content` (max 1000 chars).
  """
  def submit_behavioral_note(%{participation_record_id: record_id, provider_id: provider_id, content: content}) do
    normalized_content = normalize_notes(content)

    with {:content, content} when content != nil <- {:content, normalized_content},
         {:ok, record} <- fetch_record(record_id),
         true <- ParticipationRecord.allows_behavioral_note?(record),
         {:ok, note} <- build_note(record, provider_id, content),
         {:ok, persisted} <- insert_note(note) do
      log_publish_result(
        DomainEventBus.dispatch(@context, ParticipationEvents.behavioral_note_submitted(persisted)),
        persisted.id
      )

      {:ok, persisted}
    else
      {:content, nil} -> {:error, :blank_content}
      false -> {:error, :invalid_record_status}
      error -> error
    end
  end

  @doc """
  Reviews a behavioral note (approve or reject).

  Required params: `note_id`, `parent_id` (ownership enforced at DB level),
  `decision` (`:approve` or `:reject`). Optional: `reason`.
  """
  def review_behavioral_note(%{note_id: note_id, parent_id: parent_id, decision: decision} = params) do
    reason = Map.get(params, :reason)

    # Scoped query enforces ownership at DB level — returns :not_found if note doesn't belong to parent.
    with {:ok, note} <- fetch_note_by_parent(note_id, parent_id),
         {:ok, reviewed} <- apply_review_decision(note, decision, reason),
         {:ok, persisted} <- update_note(reviewed) do
      log_publish_result(publish_review_event(persisted, decision), persisted.id)
      {:ok, persisted}
    end
  end

  @doc """
  Revises a rejected behavioral note with new content.

  Required params: `note_id`, `provider_id` (ownership enforced at DB level), `content`.
  """
  def revise_behavioral_note(%{note_id: note_id, provider_id: provider_id, content: content}) do
    normalized_content = normalize_notes(content)

    # Scoped query enforces ownership at DB level — returns :not_found if note doesn't belong to provider.
    with {:content, content} when content != nil <- {:content, normalized_content},
         {:ok, note} <- fetch_note_by_provider(note_id, provider_id),
         {:ok, revised} <- BehavioralNote.revise(note, content),
         {:ok, persisted} <- update_note(revised) do
      log_publish_result(
        DomainEventBus.dispatch(@context, ParticipationEvents.behavioral_note_submitted(persisted)),
        persisted.id
      )

      {:ok, persisted}
    else
      {:content, nil} -> {:error, :blank_content}
      error -> error
    end
  end

  @doc """
  Anonymizes all behavioral notes for a child during GDPR account deletion.

  Replaces note content with "[Removed - account deleted]", clears rejection
  reasons, and sets status to :rejected. Uses bulk update_all for efficiency.

  Returns `{:ok, count}` with the number of notes anonymized.
  """
  def anonymize_behavioral_notes_for_child(child_id) when is_binary(child_id) do
    anonymize_notes_for_child(child_id, BehavioralNote.anonymized_attrs())
  end

  @doc "Lists pending behavioral notes for a parent awaiting review."
  def list_pending_behavioral_notes(parent_id) when is_binary(parent_id) do
    {:ok, list_notes_pending_by_parent(parent_id)}
  end

  @doc "Gets approved behavioral notes for a child."
  def get_approved_behavioral_notes(child_id) when is_binary(child_id) do
    {:ok, list_notes_approved_by_child(child_id)}
  end

  @doc "Gets a behavioral note by participation record and provider. Returns `{:ok, note}` or `{:error, :not_found}`."
  def get_behavioral_note_by_record_and_provider(record_id, provider_id)
      when is_binary(record_id) and is_binary(provider_id) do
    fetch_note_by_record_and_provider(record_id, provider_id)
  end

  @doc """
  Lists behavioral notes for multiple participation records by a single provider.

  Returns a flat list of notes. Use this instead of calling
  `get_behavioral_note_by_record_and_provider/2` per record to avoid N+1 queries.
  """
  def list_behavioral_notes_by_records_and_provider(record_ids, provider_id)
      when is_list(record_ids) and is_binary(provider_id) do
    list_notes_by_records_and_provider(record_ids, provider_id)
  end

  # ============================================================================
  # Orchestration helpers
  # ============================================================================

  defp run_attendance_action(record_id, actor_id, notes, domain_fn, event_fn) do
    notes = normalize_notes(notes)

    with {:ok, record} <- fetch_record(record_id),
         {:ok, updated} <- domain_fn.(record, actor_id, notes),
         {:ok, persisted} <- update_record(updated) do
      # Best-effort: attendance already succeeded; session fetch failure must not surface as an error.
      session =
        case fetch_session(persisted.session_id) do
          {:ok, session} ->
            session

          {:error, reason} ->
            Logger.warning("[Participation] Session fetch failed for event enrichment",
              session_id: persisted.session_id,
              reason: reason
            )

            nil
        end

      DomainEventBus.dispatch(@context, event_fn.(persisted, session))
      {:ok, persisted}
    end
  end

  defp bulk_check_in_record(record_id, checked_in_by, notes, session) do
    with {:ok, record} <- fetch_record(record_id),
         {:ok, checked_in} <- ParticipationRecord.check_in(record, checked_in_by, notes),
         {:ok, persisted} <- update_record(checked_in) do
      session = resolve_session_best_effort(session, persisted.session_id)
      publish_bulk_check_in(persisted, session)
      {:ok, persisted, session}
    else
      {:error, reason} -> {:error, record_id, reason}
    end
  end

  defp resolve_session_best_effort(%ProgramSession{} = session, _session_id), do: session

  defp resolve_session_best_effort(nil, session_id) do
    case fetch_session(session_id) do
      {:ok, session} ->
        session

      {:error, reason} ->
        Logger.warning("[Participation] Session fetch failed for event enrichment",
          session_id: session_id,
          reason: reason
        )

        nil
    end
  end

  defp categorize_bulk_result({:ok, record}, acc), do: %{acc | successful: [record | acc.successful]}

  defp categorize_bulk_result({:error, record_id, reason}, acc), do: %{acc | failed: [{record_id, reason} | acc.failed]}

  defp mark_remaining_as_absent(session) do
    registered =
      session.id
      |> list_records_by_session()
      |> Enum.filter(&(&1.status == :registered))

    {:ok, _count} = mark_records_absent(Enum.map(registered, & &1.id))

    Enum.each(registered, fn record ->
      DomainEventBus.dispatch(
        @context,
        ParticipationEvents.child_marked_absent(%{record | status: :absent}, session)
      )
    end)

    :ok
  end

  defp validate_correction_reason(:admin, %{reason: reason}) when is_binary(reason) do
    if String.trim(reason) == "", do: {:error, :reason_required}, else: :ok
  end

  defp validate_correction_reason(:admin, _params), do: {:error, :reason_required}
  defp validate_correction_reason(_role, _params), do: :ok

  defp build_correction_attrs(:admin, record, params) do
    params
    |> base_correction_attrs()
    |> apply_admin_reason_notes(record, params)
  end

  defp build_correction_attrs(role, _record, params) when role in [:provider, :staff] do
    notes =
      params
      |> Map.take([:check_in_notes, :check_out_notes])
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    Map.merge(base_correction_attrs(params), notes)
  end

  defp base_correction_attrs(params) do
    params
    |> Map.take([:status, :check_in_at, :check_out_at])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  # Admin-only: append the supplied reason to the field whose change motivated it.
  defp apply_admin_reason_notes(attrs, record, %{reason: reason}) when is_binary(reason) do
    trimmed = String.trim(reason)

    cond do
      Map.has_key?(attrs, :check_in_at) and attrs.check_in_at != record.check_in_at ->
        Map.put(attrs, :check_in_notes, append_admin_note(record.check_in_notes, trimmed))

      Map.has_key?(attrs, :check_out_at) and attrs.check_out_at != record.check_out_at ->
        Map.put(attrs, :check_out_notes, append_admin_note(record.check_out_notes, trimmed))

      Map.has_key?(attrs, :status) and attrs.status != record.status ->
        Map.put(attrs, :check_in_notes, append_admin_note(record.check_in_notes, trimmed))

      true ->
        attrs
    end
  end

  defp apply_admin_reason_notes(attrs, _record, _params), do: attrs

  defp append_admin_note(existing, reason) do
    note = "[Admin correction] #{reason}"

    case existing do
      nil -> note
      "" -> note
      existing -> "#{existing} | #{note}"
    end
  end

  defp build_note(record, provider_id, content) do
    BehavioralNote.new(%{
      id: Ecto.UUID.generate(),
      participation_record_id: record.id,
      child_id: record.child_id,
      parent_id: record.parent_id,
      provider_id: provider_id,
      content: content
    })
  end

  defp apply_review_decision(note, :approve, _reason), do: BehavioralNote.approve(note)
  defp apply_review_decision(note, :reject, reason), do: BehavioralNote.reject(note, reason)
  defp apply_review_decision(_note, _decision, _reason), do: {:error, :invalid_decision}

  defp batch_resolve_roster(records) do
    child_ids = records |> Enum.map(& &1.child_id) |> Enum.uniq()
    child_info_map = ChildInfoResolver.resolve_children_info(child_ids)

    # Behavioral notes are only visible when parent has consented — filter before fetching.
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

    {child_info_map, notes_map}
  end

  defp build_enrichment_fields(child_info, notes) do
    %{
      child_name: "#{child_info.first_name} #{child_info.last_name}",
      child_first_name: child_info.first_name,
      child_last_name: child_info.last_name,
      allergies: child_info.allergies,
      support_needs: child_info.support_needs,
      emergency_contact: child_info.emergency_contact,
      behavioral_notes: notes
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

  defp publish_session_completed(session) do
    extra_payload = resolve_provider_details(session.program_id)
    event = ParticipationEvents.session_completed(session, extra_payload: extra_payload)
    DomainEventBus.dispatch(@context, event)
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

  defp publish_bulk_check_in(record, %ProgramSession{} = session) do
    DomainEventBus.dispatch(@context, ParticipationEvents.child_checked_in(record, session))
  end

  defp publish_bulk_check_in(record, nil) do
    DomainEventBus.dispatch(@context, ParticipationEvents.child_checked_in(record))
  end

  defp publish_review_event(note, :approve) do
    DomainEventBus.dispatch(@context, ParticipationEvents.behavioral_note_approved(note))
  end

  defp publish_review_event(note, :reject) do
    DomainEventBus.dispatch(@context, ParticipationEvents.behavioral_note_rejected(note))
  end

  defp safe_publish_roster_seeded(session_id, program_id, count) do
    event = ParticipationEvents.roster_seeded(session_id, program_id, count)

    case DomainEventBus.dispatch(@context, event) do
      :ok ->
        :ok

      {:error, failures} ->
        Logger.warning(
          "[Participation] Roster-seeded event dispatch had handler failures: #{inspect(failures)}",
          session_id: session_id,
          program_id: program_id
        )
    end
  rescue
    error ->
      Logger.error(
        "[Participation] Roster seeded but event dispatch failed: #{Exception.message(error)}",
        session_id: session_id,
        program_id: program_id,
        step: "event_dispatch",
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )
  end

  defp log_publish_result(:ok, _id), do: :ok

  defp log_publish_result({:error, reason}, id) do
    Logger.warning("[Participation] PubSub publish failed", id: id, reason: inspect(reason))
  end

  # ============================================================================
  # Persistence — sessions
  # ============================================================================

  defp insert_session(%ProgramSession{} = session) do
    db_interaction operation: :create, entity: "session" do
      session
      |> Map.from_struct()
      |> ProgramSession.create_changeset()
      |> Repo.insert()
      |> handle_session_insert()
    end
  end

  defp fetch_session(id) when is_binary(id) do
    db_interaction operation: :get_by_id, entity: "session" do
      case Repo.get(ProgramSession, id) do
        nil -> {:error, :not_found}
        session -> {:ok, session}
      end
    end
  end

  defp update_session(%ProgramSession{} = session) do
    db_interaction operation: :update, entity: "session" do
      with {:ok, schema} <- RepositoryHelpers.get_schema_by_uuid(ProgramSession, session.id) do
        attrs = Map.take(session, [:status, :location, :notes, :max_capacity, :lock_version])

        schema
        |> ProgramSession.update_changeset(attrs)
        |> Repo.update()
        |> handle_session_update()
      end
    end
  end

  defp list_sessions_by_program(program_id) do
    db_interaction operation: :list_by_program, entity: "session" do
      from(s in ProgramSession,
        where: s.program_id == ^program_id,
        order_by: [asc: s.session_date, asc: s.start_time]
      )
      |> Repo.all()
    end
  end

  defp list_sessions_today(date) do
    db_interaction operation: :list_today_sessions, entity: "session" do
      from(s in ProgramSession, where: s.session_date == ^date, order_by: [asc: s.start_time])
      |> Repo.all()
    end
  end

  defp handle_session_insert({:ok, schema}), do: {:ok, schema}

  defp handle_session_insert({:error, %Ecto.Changeset{errors: errors} = changeset}) do
    if EctoErrorHelpers.any_unique_constraint_violation?(errors) do
      {:error, :duplicate_session}
    else
      {:error, ErrorIds.session_create_failed(changeset)}
    end
  end

  defp handle_session_update({:ok, schema}), do: {:ok, schema}

  defp handle_session_update({:error, %Ecto.Changeset{} = changeset}) do
    if changeset.errors[:lock_version] do
      {:error, :stale_data}
    else
      {:error, ErrorIds.session_update_failed(changeset)}
    end
  end

  # ============================================================================
  # Persistence — participation records
  # ============================================================================

  defp fetch_record(id) when is_binary(id) do
    db_interaction operation: :get_by_id, entity: "participation" do
      case Repo.get(ParticipationRecord, id) do
        nil -> {:error, :not_found}
        record -> {:ok, record}
      end
    end
  end

  defp update_record(%ParticipationRecord{} = record) do
    db_interaction operation: :update, entity: "participation" do
      with {:ok, schema} <- RepositoryHelpers.get_schema_by_uuid(ParticipationRecord, record.id) do
        attrs = Map.take(record, @record_update_fields)

        schema
        |> ParticipationRecord.update_changeset(attrs)
        |> Repo.update()
        |> handle_record_update()
      end
    end
  rescue
    Ecto.StaleEntryError -> {:error, :stale_data}
  end

  defp list_records_by_session(session_id) do
    db_interaction operation: :list_by_session, entity: "participation" do
      ParticipationQueries.base()
      |> ParticipationQueries.by_session(session_id)
      |> ParticipationQueries.order_by_inserted_desc()
      |> Repo.all()
    end
  end

  defp list_records_by_child(child_id) do
    db_interaction operation: :list_by_child, entity: "participation" do
      ParticipationQueries.base()
      |> ParticipationQueries.by_child(child_id)
      |> ParticipationQueries.preload_session()
      |> ParticipationQueries.order_by_inserted_desc()
      |> Repo.all()
    end
  end

  defp list_records_by_child_and_date_range(child_id, start_date, end_date) do
    db_interaction operation: :list_by_child_and_date_range, entity: "participation" do
      ParticipationQueries.base()
      |> ParticipationQueries.by_child(child_id)
      |> ParticipationQueries.by_date_range(start_date, end_date)
      |> ParticipationQueries.order_by_session_date_desc()
      |> Repo.all()
    end
  end

  defp list_records_by_children(child_ids) do
    db_interaction operation: :list_by_children, entity: "participation" do
      ParticipationQueries.base()
      |> ParticipationQueries.by_children(child_ids)
      |> ParticipationQueries.preload_session()
      |> ParticipationQueries.order_by_inserted_desc()
      |> Repo.all()
    end
  end

  defp list_records_by_children_and_date_range(child_ids, start_date, end_date) do
    db_interaction operation: :list_by_children_and_date_range, entity: "participation" do
      ParticipationQueries.base()
      |> ParticipationQueries.by_children(child_ids)
      |> ParticipationQueries.by_date_range(start_date, end_date)
      |> ParticipationQueries.order_by_session_date_desc()
      |> Repo.all()
    end
  end

  defp mark_records_absent([]), do: {:ok, 0}

  defp mark_records_absent(record_ids) when is_list(record_ids) do
    db_interaction operation: :mark_absent_batch, entity: "participation" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {count, _} =
        from(r in ParticipationRecord, where: r.id in ^record_ids and r.status == :registered)
        |> Repo.update_all(inc: [lock_version: 1], set: [status: :absent, updated_at: now])

      {:ok, count}
    end
  end

  defp seed_records(_session_id, []), do: {:ok, 0}

  defp seed_records(session_id, child_ids) when is_binary(session_id) and is_list(child_ids) do
    db_interaction operation: :seed_batch, entity: "participation" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      rows =
        Enum.map(child_ids, fn child_id ->
          %{
            id: Ecto.UUID.generate(),
            session_id: session_id,
            child_id: child_id,
            status: :registered,
            lock_version: 1,
            inserted_at: now,
            updated_at: now
          }
        end)

      {count, _} =
        Repo.insert_all(ParticipationRecord, rows,
          on_conflict: :nothing,
          conflict_target: [:session_id, :child_id]
        )

      {:ok, count}
    end
  end

  defp handle_record_update({:ok, schema}), do: {:ok, schema}

  defp handle_record_update({:error, %Ecto.Changeset{} = changeset}) do
    if changeset.errors[:lock_version] do
      {:error, :stale_data}
    else
      {:error, ErrorIds.participation_record_update_failed(changeset)}
    end
  end

  # ============================================================================
  # Persistence — behavioral notes
  # ============================================================================

  defp insert_note(%BehavioralNote{} = note) do
    db_interaction operation: :create, entity: "behavioral_note" do
      note
      |> Map.from_struct()
      |> BehavioralNote.create_changeset()
      |> Repo.insert()
      |> handle_note_insert()
    end
  end

  defp update_note(%BehavioralNote{} = note) do
    db_interaction operation: :update, entity: "behavioral_note" do
      case Repo.get(BehavioralNote, note.id) do
        nil ->
          {:error, :not_found}

        schema ->
          attrs = Map.take(note, @note_update_fields)

          schema
          |> BehavioralNote.update_changeset(attrs)
          |> Repo.update()
          |> handle_note_update()
      end
    end
  end

  defp list_notes_pending_by_parent(parent_id) do
    db_interaction operation: :list_pending_by_parent, entity: "behavioral_note" do
      BehavioralNoteQueries.base()
      |> BehavioralNoteQueries.by_parent(parent_id)
      |> BehavioralNoteQueries.pending()
      |> BehavioralNoteQueries.order_by_submitted_desc()
      |> Repo.all()
    end
  end

  defp list_notes_approved_by_child(child_id) do
    db_interaction operation: :list_approved_by_child, entity: "behavioral_note" do
      BehavioralNoteQueries.base()
      |> BehavioralNoteQueries.by_child(child_id)
      |> BehavioralNoteQueries.approved()
      |> BehavioralNoteQueries.order_by_submitted_desc()
      |> Repo.all()
    end
  end

  defp list_notes_approved_by_children(child_ids) do
    db_interaction operation: :list_approved_by_children, entity: "behavioral_note" do
      BehavioralNoteQueries.base()
      |> BehavioralNoteQueries.approved()
      |> where([note: n], n.child_id in ^child_ids)
      |> BehavioralNoteQueries.order_by_submitted_desc()
      |> Repo.all()
      |> Enum.group_by(& &1.child_id)
    end
  end

  defp list_notes_by_records_and_provider(record_ids, provider_id) do
    db_interaction operation: :list_by_records_and_provider, entity: "behavioral_note" do
      BehavioralNoteQueries.base()
      |> BehavioralNoteQueries.by_participation_records(record_ids)
      |> BehavioralNoteQueries.by_provider(provider_id)
      |> Repo.all()
    end
  end

  defp fetch_note_by_parent(id, parent_id) do
    db_interaction operation: :get_by_id_and_parent, entity: "behavioral_note" do
      BehavioralNoteQueries.base()
      |> BehavioralNoteQueries.by_parent(parent_id)
      |> where([note: n], n.id == ^id)
      |> Repo.one()
      |> case do
        nil -> {:error, :not_found}
        schema -> {:ok, schema}
      end
    end
  end

  defp fetch_note_by_provider(id, provider_id) do
    db_interaction operation: :get_by_id_and_provider, entity: "behavioral_note" do
      BehavioralNoteQueries.base()
      |> BehavioralNoteQueries.by_provider(provider_id)
      |> where([note: n], n.id == ^id)
      |> Repo.one()
      |> case do
        nil -> {:error, :not_found}
        schema -> {:ok, schema}
      end
    end
  end

  defp fetch_note_by_record_and_provider(record_id, provider_id) do
    db_interaction operation: :get_by_participation_record_and_provider, entity: "behavioral_note" do
      BehavioralNoteQueries.base()
      |> BehavioralNoteQueries.by_participation_record(record_id)
      |> BehavioralNoteQueries.by_provider(provider_id)
      |> Repo.one()
      |> case do
        nil -> {:error, :not_found}
        schema -> {:ok, schema}
      end
    end
  end

  defp anonymize_notes_for_child(child_id, anonymized_attrs) when is_binary(child_id) and is_map(anonymized_attrs) do
    db_interaction operation: :anonymize_all_for_child, entity: "behavioral_note" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # update_all bypasses Ecto.Enum casting — convert :status atom to string manually.
      set_fields =
        anonymized_attrs
        |> convert_note_enum_fields()
        |> Enum.to_list()
        |> Keyword.new()
        |> Keyword.put(:updated_at, now)

      {count, _} =
        BehavioralNote
        |> where([n], n.child_id == ^child_id)
        |> Repo.update_all(set: set_fields)

      {:ok, count}
    end
  end

  defp handle_note_insert({:ok, schema}), do: {:ok, schema}

  defp handle_note_insert({:error, %Ecto.Changeset{errors: errors} = changeset}) do
    if EctoErrorHelpers.any_unique_constraint_violation?(errors) do
      {:error, :duplicate_note}
    else
      Logger.warning("[Participation] Behavioral note validation failed on insert",
        errors: inspect(changeset.errors)
      )

      {:error, :validation_failed}
    end
  end

  defp handle_note_update({:ok, schema}), do: {:ok, schema}

  defp handle_note_update({:error, %Ecto.Changeset{} = changeset}) do
    Logger.warning("[Participation] Behavioral note validation failed on update",
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
