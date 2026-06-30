defmodule KlassHero.Participation do
  @moduledoc """
  Public API for the Participation bounded context.

  Covers session lifecycle, check-in/check-out, attendance, and behavioral notes.
  """

  alias KlassHero.Participation.Application.Commands.{
    AnonymizeBehavioralNotesForChild,
    BulkCheckIn,
    CompleteSession,
    CorrectAttendance,
    CreateSession,
    RecordCheckIn,
    RecordCheckOut,
    ReviewBehavioralNote,
    ReviseBehavioralNote,
    StartSession,
    SubmitBehavioralNote
  }

  alias KlassHero.Participation.Application.Queries.{
    GetApprovedBehavioralNotes,
    GetBehavioralNoteForRecord,
    GetParticipationHistory,
    GetParticipationRecord,
    GetSessionWithRoster,
    ListPendingBehavioralNotes,
    ListProviderSessions,
    ListSessions
  }

  alias KlassHero.Participation.ParticipationRecord
  alias KlassHero.Participation.ProgramSession

  @doc """
  Creates a new program session.

  Required params: `program_id`, `session_date`, `start_time`, `end_time`.

  Returns `{:ok, session}`, `{:error, :invalid_time_range}`, or `{:error, :duplicate_session}`.
  """
  def create_session(params) when is_map(params) do
    CreateSession.execute(params)
  end

  @doc """
  Starts a scheduled session.

  Returns `{:ok, session}`, `{:error, :not_found}`, or `{:error, :invalid_status_transition}`.
  """
  def start_session(session_id) when is_binary(session_id) do
    StartSession.execute(session_id)
  end

  @doc """
  Completes an in-progress session, marking all registered (not checked-in) children as absent.

  Returns `{:ok, session}`, `{:error, :not_found}`, or `{:error, :invalid_status_transition}`.
  """
  def complete_session(session_id) when is_binary(session_id) do
    CompleteSession.execute(session_id)
  end

  @doc """
  Checks in a child to a session.

  Required params: `record_id`, `checked_in_by`. Optional: `notes`.

  Returns `{:ok, record}`, `{:error, :not_found}`, or `{:error, :invalid_status_transition}`.
  """
  def record_check_in(params) when is_map(params) do
    RecordCheckIn.execute(params)
  end

  @doc """
  Checks out a child from a session.

  Required params: `record_id`, `checked_out_by`. Optional: `notes`.

  Returns `{:ok, record}`, `{:error, :not_found}`, or `{:error, :invalid_status_transition}`.
  """
  def record_check_out(params) when is_map(params) do
    RecordCheckOut.execute(params)
  end

  @doc """
  Checks in multiple children at once.

  Required params: `record_ids`, `checked_in_by`. Optional: `notes`.

  Returns a map with `successful` (records) and `failed` (`{record_id, reason}` tuples).
  """
  def bulk_check_in(params) when is_map(params) do
    BulkCheckIn.execute(params)
  end

  @doc "Admin-corrects a participation record's attendance data."
  def correct_attendance(params) when is_map(params) do
    CorrectAttendance.execute(params)
  end

  @doc """
  Submits a behavioral note for a participation record.

  Required params: `participation_record_id`, `provider_id`, `content` (max 1000 chars).
  """
  def submit_behavioral_note(params) when is_map(params) do
    SubmitBehavioralNote.execute(params)
  end

  @doc """
  Reviews a behavioral note (approve or reject).

  Required params: `note_id`, `parent_id` (ownership enforced at DB level),
  `decision` (`:approve` or `:reject`). Optional: `reason`.
  """
  def review_behavioral_note(params) when is_map(params) do
    ReviewBehavioralNote.execute(params)
  end

  @doc """
  Revises a rejected behavioral note with new content.

  Required params: `note_id`, `provider_id` (ownership enforced at DB level), `content`.
  """
  def revise_behavioral_note(params) when is_map(params) do
    ReviseBehavioralNote.execute(params)
  end

  @doc """
  Anonymizes all behavioral notes for a child during GDPR account deletion.

  Replaces note content with "[Removed - account deleted]", clears rejection
  reasons, and sets status to :rejected. Uses bulk update_all for efficiency.

  Returns `{:ok, count}` with the number of notes anonymized.
  """
  def anonymize_behavioral_notes_for_child(child_id) when is_binary(child_id) do
    AnonymizeBehavioralNotesForChild.execute(child_id)
  end

  @doc "Lists sessions, optionally filtered by `program_id` or `date`."
  def list_sessions(params \\ %{}) when is_map(params) do
    ListSessions.execute(params)
  end

  @doc "Lists sessions with enriched data for admin dashboard."
  def list_admin_sessions(filters \\ %{}) when is_map(filters) do
    ListSessions.execute_admin(filters)
  end

  @doc "Returns the list of valid session statuses."
  def session_statuses do
    ProgramSession.valid_statuses()
  end

  @doc "Returns the list of valid participation record statuses."
  def record_statuses do
    ParticipationRecord.valid_statuses()
  end

  @doc "Lists sessions for a provider on a specific date (defaults to today)."
  def list_provider_sessions(provider_id, date \\ nil) when is_binary(provider_id) do
    params = %{provider_id: provider_id}
    params = if date, do: Map.put(params, :date, date), else: params
    ListProviderSessions.execute(params)
  end

  @doc """
  Retrieves a session with its complete roster.

  Returns `{:ok, %{session: session, roster: roster}}` or `{:error, :not_found}`.
  """
  def get_session_with_roster(session_id) when is_binary(session_id) do
    GetSessionWithRoster.execute(session_id)
  end

  @doc """
  Like `get_session_with_roster/1` but enriches records with resolved child names for UI display.

  Returns `{:ok, session}` (with `participation_records` populated) or `{:error, :not_found}`.
  """
  def get_session_with_roster_enriched(session_id) when is_binary(session_id) do
    GetSessionWithRoster.execute_enriched(session_id)
  end

  @doc "Retrieves a participation record by ID. Returns `{:ok, record}` or `{:error, :not_found}`."
  def get_participation_record(record_id) when is_binary(record_id) do
    GetParticipationRecord.execute(record_id)
  end

  @doc """
  Retrieves participation history for one or more children.

  Accepts `child_id` or `child_ids`, with optional `start_date`/`end_date`.
  Returns `{:ok, records}` ordered by date descending.
  """
  def get_participation_history(params) when is_map(params) do
    GetParticipationHistory.execute(params)
  end

  @doc "Lists pending behavioral notes for a parent awaiting review."
  def list_pending_behavioral_notes(parent_id) when is_binary(parent_id) do
    ListPendingBehavioralNotes.execute(parent_id)
  end

  @doc "Gets approved behavioral notes for a child."
  def get_approved_behavioral_notes(child_id) when is_binary(child_id) do
    GetApprovedBehavioralNotes.execute(child_id)
  end

  @doc "Gets a behavioral note by participation record and provider. Returns `{:ok, note}` or `{:error, :not_found}`."
  def get_behavioral_note_by_record_and_provider(record_id, provider_id)
      when is_binary(record_id) and is_binary(provider_id) do
    GetBehavioralNoteForRecord.execute(record_id, provider_id)
  end

  @doc """
  Lists behavioral notes for multiple participation records by a single provider.

  Returns a flat list of notes. Use this instead of calling
  `get_behavioral_note_by_record_and_provider/2` per record to avoid N+1 queries.
  """
  def list_behavioral_notes_by_records_and_provider(record_ids, provider_id)
      when is_list(record_ids) and is_binary(provider_id) do
    GetBehavioralNoteForRecord.execute_batch(record_ids, provider_id)
  end
end
