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

  alias KlassHero.Accounts.Scope
  alias KlassHero.Participation.Attendance
  alias KlassHero.Participation.ChildInfoResolver
  alias KlassHero.Participation.Events
  alias KlassHero.Participation.Notifications
  alias KlassHero.Participation.ProgramProviderResolver
  alias KlassHero.Participation.ProgramSession
  alias KlassHero.Participation.SessionAuthorization
  alias KlassHero.Participation.SessionNotes
  alias KlassHero.Participation.Sessions
  alias KlassHero.Shared.Outbox

  require Logger

  @context __MODULE__

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
        SessionNotes.list_approved_notes_for_children(consented_child_ids)
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

  # ============================================================================
  # Session notes
  # ============================================================================

  @doc "Submits a session note about a child, on behalf of `scope`."
  defdelegate submit_session_note(scope, params), to: SessionNotes

  @doc "Reviews a session note (approve or reject), on behalf of `scope`."
  defdelegate review_session_note(scope, params), to: SessionNotes

  @doc "Revises a rejected session note with new content, on behalf of `scope`."
  defdelegate revise_session_note(scope, params), to: SessionNotes

  @doc "Anonymizes all session notes for a child during GDPR account deletion."
  defdelegate anonymize_session_notes_for_child(child_id), to: SessionNotes

  @doc "Lists the session notes awaiting a parent's review."
  defdelegate list_pending_session_notes(parent_id), to: SessionNotes

  @doc "Lists a child's approved session notes."
  defdelegate get_approved_session_notes(child_id), to: SessionNotes

  @doc "Fetches one provider's note on one participation record."
  defdelegate get_session_note_by_record_and_provider(record_id, provider_id), to: SessionNotes

  @doc "Batch sibling of `get_session_note_by_record_and_provider/2`."
  defdelegate list_session_notes_by_records_and_provider(record_ids, provider_id), to: SessionNotes

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
end
