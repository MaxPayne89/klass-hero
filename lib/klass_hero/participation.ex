defmodule KlassHero.Participation do
  @moduledoc """
  Public API for the Participation bounded context.

  Covers session lifecycle, check-in/check-out, attendance, and session notes.

  This module is a thin facade: every function delegates to a sub-domain module
  under `KlassHero.Participation.*` — `Sessions`, `Attendance`, `SessionNotes` —
  or to the one use case that spans two of them, `CompleteSession`. Consumers
  call only this module.

  The state machines live on the schema structs (`ProgramSession`,
  `ParticipationRecord`, `SessionNote`). Cross-context reads route through the
  owning contexts' public facades (`ProgramCatalog`, `Provider`) and the local
  `*Resolver` ACL adapters.

  Tracing lives one level down, in the modules that do the work: a
  `context_span` opened here would name the facade rather than the operation.
  They still report `context.name` as `Participation`, which is derived from the
  second module segment rather than the last (#1424).
  """

  alias KlassHero.Participation.Attendance
  alias KlassHero.Participation.CompleteSession
  alias KlassHero.Participation.Notifications
  alias KlassHero.Participation.SessionNotes
  alias KlassHero.Participation.Sessions

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

  @doc "Completes an in-progress session, sweeping its roster to absent."
  defdelegate complete_session(scope, session_id), to: CompleteSession, as: :execute

  @doc "Retrieves a session with its complete roster."
  defdelegate get_session_with_roster(session_id), to: Sessions

  @doc "Like `get_session_with_roster/1`, with child names resolved for display."
  defdelegate get_session_with_roster_enriched(session_id), to: Sessions

  @doc "Retrieves a session by id. Returns `{:ok, session}` or `{:error, :not_found}`."
  defdelegate get_session(session_id), to: Sessions

  @doc "Batch sibling of `get_session/1`; unknown ids are omitted."
  defdelegate get_sessions(session_ids), to: Sessions

  @doc "Returns the list of valid session statuses."
  defdelegate session_statuses(), to: Sessions

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
end
