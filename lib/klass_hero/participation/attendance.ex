defmodule KlassHero.Participation.Attendance do
  @moduledoc """
  Attendance: the roster and what happens to a child on it.

  Owns `ParticipationRecord` and `AttendanceTransition` — seeding a session's
  roster, checking a child in and out, marking an absence, correcting a record
  after the fact, and the history reads over all of it.

  Every write authorizes here, at the write, against the caller's scope
  (ADR-0017). `authorize_for_record/2` is that single guard; `SessionNotes` calls
  it too, because a note about a child at a session is authorized by the same
  question as that child's attendance.

  State-changing operations open a `context_span`; reads stay bare.
  """

  use KlassHero.Shared.Tracing

  import Ecto.Query

  alias KlassHero.Accounts.Scope
  alias KlassHero.Enrollment
  alias KlassHero.Participation.AttendanceTransition
  alias KlassHero.Participation.Events
  alias KlassHero.Participation.Notifications
  alias KlassHero.Participation.ParticipationQueries
  alias KlassHero.Participation.ParticipationRecord
  alias KlassHero.Participation.ProgramSession
  alias KlassHero.Participation.SessionAuthorization
  alias KlassHero.Participation.Sessions
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.RepositoryHelpers
  alias KlassHero.Shared.ErrorIds
  alias KlassHero.Shared.Outbox

  require Logger

  @context KlassHero.Participation

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

  @doc """
  Roster size and attendance tally for the given sessions, keyed by session id.

  One grouped query for the whole list, so a day's sessions cost the same as one.
  Sessions with an empty roster are absent from the map rather than mapping to
  zeroes — callers decide what "no roster yet" should render as.
  """
  @spec session_attendance_counts([String.t()]) ::
          %{optional(String.t()) => %{roster: non_neg_integer(), checked_in: non_neg_integer()}}
  def session_attendance_counts([]), do: %{}

  def session_attendance_counts(session_ids) when is_list(session_ids) do
    from(r in ParticipationRecord,
      where: r.session_id in ^session_ids,
      group_by: r.session_id,
      select: {
        r.session_id,
        count(r.id),
        count(fragment("CASE WHEN ? = ANY(?) THEN 1 END", r.status, ^ParticipationRecord.checked_in_statuses()))
      }
    )
    |> Repo.all()
    |> Map.new(fn {id, roster, checked_in} -> {id, %{roster: roster, checked_in: checked_in}} end)
  end

  @doc """
  Counts an already-loaded roster into the same shape as `session_attendance_counts/1`.

  Live updates arrive with the roster already fetched, so recounting in memory
  keeps a check-in from costing another query.
  """
  @spec attendance_from_roster([map()]) :: %{roster: non_neg_integer(), checked_in: non_neg_integer()}
  def attendance_from_roster(roster) when is_list(roster),
    do: roster |> Enum.map(& &1.record) |> attendance_from_records()

  @doc """
  Same tally as `attendance_from_roster/1`, for a bare list of participation records.

  Detail pages hold enriched records rather than roster entries.
  """
  @spec attendance_from_records([map()]) :: %{roster: non_neg_integer(), checked_in: non_neg_integer()}
  def attendance_from_records(records) when is_list(records) do
    %{
      roster: length(records),
      checked_in: Enum.count(records, &("#{&1.status}" in ParticipationRecord.checked_in_statuses()))
    }
  end

  @doc """
  Seeds a session roster with the program's enrolled children. Best-effort: always returns `:ok`.

  Invoked by the `session_created` integration-event handler.
  """
  @spec seed_session_roster(String.t(), String.t()) :: :ok
  def seed_session_roster(session_id, program_id) when is_binary(session_id) and is_binary(program_id) do
    context_span entity: "participation_record" do
      child_ids = Enrollment.list_enrolled_child_ids(program_id)

      # max_capacity is not checked: capacity is an enrollment-time concern, not a roster gate.
      {:ok, {count, roster_events}} = seed_roster_records(session_id, program_id, child_ids)

      Logger.info(
        "[Participation] Seeded roster — enrolled=#{length(child_ids)} inserted=#{count} skipped=#{length(child_ids) - count}",
        session_id: session_id,
        program_id: program_id
      )

      Notifications.notify_all(roster_events)

      :ok
    end
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

  @doc """
  Seeds the rosters of a batch of sessions that share one program. Best-effort:
  always returns `:ok`.

  Invoked by the `sessions_generated` integration-event handler. The program's
  enrolled children are resolved once for the batch, rather than once per
  session as `seed_session_roster/2` would.
  """
  @spec seed_rosters_for_sessions([String.t()], String.t()) :: :ok
  def seed_rosters_for_sessions([], _program_id), do: :ok

  def seed_rosters_for_sessions(session_ids, program_id) when is_list(session_ids) and is_binary(program_id) do
    context_span entity: "participation_record" do
      child_ids = Enrollment.list_enrolled_child_ids(program_id)

      for session_id <- session_ids do
        {:ok, {_count, events}} = seed_roster_records(session_id, program_id, child_ids)
        Notifications.notify_all(events)
      end

      Logger.info(
        "[Participation] Seeded generated rosters — sessions=#{length(session_ids)} enrolled=#{length(child_ids)}",
        program_id: program_id
      )

      :ok
    end
  rescue
    error ->
      Logger.error(
        "[Participation] Failed to seed generated rosters: #{Exception.message(error)}",
        program_id: program_id,
        step: "acl_query_or_bulk_insert",
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      :ok
  end

  @doc """
  Places a newly-enrolled child on the roster of every upcoming scheduled session
  of the program. Best-effort: always returns `:ok`.

  Invoked by the `enrollment_created` integration-event handler. Sessions in the
  past, in progress, completed or cancelled are left alone — enrolling today must
  never rewrite attendance history.
  """
  @spec backfill_roster_for_enrollment(String.t(), String.t()) :: :ok
  def backfill_roster_for_enrollment(child_id, program_id) when is_binary(child_id) and is_binary(program_id) do
    context_span entity: "participation_record" do
      session_ids = Sessions.upcoming_scheduled_session_ids(program_id)

      # One event per session that actually gained a row, so each session's
      # read-model count moves by exactly the number of rows it gained.
      {:ok, {seeded_ids, backfill_events}} =
        Outbox.transact_with_events(@context, fn ->
          {:ok, seeded_ids} = seed_child_records(session_ids, child_id)
          {:ok, seeded_ids, Enum.map(seeded_ids, &Events.roster_seeded(&1, program_id, 1))}
        end)

      Logger.info(
        "[Participation] Backfilled roster — upcoming=#{length(session_ids)} inserted=#{length(seeded_ids)}",
        child_id: child_id,
        program_id: program_id
      )

      Notifications.notify_all(backfill_events)

      :ok
    end
  rescue
    error ->
      Logger.error(
        "[Participation] Failed to backfill roster: #{Exception.message(error)}",
        child_id: child_id,
        program_id: program_id,
        step: "session_query_or_bulk_insert",
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      :ok
  end

  # ============================================================================
  # Attendance
  # ============================================================================

  @doc """
  Checks in a child to a session, on behalf of `scope`.

  The actor's identity and role are derived from the scope — the caller cannot
  name who did this, only prove who it is. Options: `:notes`.

  Returns `{:ok, record}`, `{:error, :unauthorized}`, `{:error, :not_found}`, or
  `{:error, :invalid_status_transition}`.
  """
  @spec record_check_in(Scope.t(), String.t(), keyword()) ::
          {:ok, ParticipationRecord.t()} | {:error, atom()}
  def record_check_in(%Scope{} = scope, record_id, opts \\ []) when is_binary(record_id) do
    context_span entity: "participation_record" do
      run_attendance_action(
        scope,
        record_id,
        Keyword.get(opts, :notes),
        &ParticipationRecord.check_in/3,
        &Events.child_checked_in/2
      )
    end
  end

  @doc """
  Checks out a child from a session, on behalf of `scope`.

  Options: `:notes`. Returns `{:ok, record}`, `{:error, :unauthorized}`,
  `{:error, :not_found}`, or `{:error, :invalid_status_transition}`.
  """
  @spec record_check_out(Scope.t(), String.t(), keyword()) ::
          {:ok, ParticipationRecord.t()} | {:error, atom()}
  def record_check_out(%Scope{} = scope, record_id, opts \\ []) when is_binary(record_id) do
    context_span entity: "participation_record" do
      run_attendance_action(
        scope,
        record_id,
        Keyword.get(opts, :notes),
        &ParticipationRecord.check_out/3,
        &Events.child_checked_out/2
      )
    end
  end

  @doc """
  Marks a child absent by hand, on behalf of `scope`.

  The deliberate counterpart to the batch absence that `complete_session/2`
  applies to every straggler: this one names an actor and takes a reason, and
  the `AttendanceTransition` it writes is where the two are told apart (#1329).

  Options: `:reason`. Returns `{:ok, record}`, `{:error, :unauthorized}`,
  `{:error, :not_found}`, or `{:error, :invalid_status_transition}`.
  """
  @spec record_absence(Scope.t(), String.t(), keyword()) ::
          {:ok, ParticipationRecord.t()} | {:error, atom()}
  def record_absence(%Scope{} = scope, record_id, opts \\ []) when is_binary(record_id) do
    context_span entity: "participation_record" do
      run_attendance_action(
        scope,
        record_id,
        Keyword.get(opts, :reason),
        &ParticipationRecord.mark_absent/3,
        &Events.child_marked_absent/2
      )
    end
  end

  @doc """
  Corrects a participation record's attendance data, on behalf of `scope`.

  The correction rules follow the scope's derived role: an `:admin` must supply a
  `:reason`, which is appended to the notes of whichever field changed; a
  `:provider` or `:staff` actor corrects their own roster without one.

  Announces itself like every other attendance write. Until #1329 it ended at a
  bare update: no event, no broadcast — so a correction reached neither the other
  connected clients nor `ProviderSessionDetails`, whose `checked_in_count` then
  drifted from what a rebuild would compute.
  """
  @spec correct_attendance(Scope.t(), String.t(), map()) ::
          {:ok, ParticipationRecord.t()} | {:error, atom()}
  def correct_attendance(%Scope{} = scope, record_id, attrs) when is_binary(record_id) do
    context_span entity: "participation_record" do
      with {:ok, record} <- fetch_record(record_id),
           {:ok, actor_role} <- authorize_for_record(scope, record),
           :ok <- validate_correction_reason(actor_role, attrs),
           correction_attrs = build_correction_attrs(actor_role, record, attrs),
           {:ok, corrected} <- ParticipationRecord.admin_correct(record, correction_attrs),
           {:ok, {persisted, events}} <-
             correct_record_with_event(record, corrected, scope.user.id, Map.get(attrs, :reason)) do
        Notifications.notify_all(events)
        {:ok, persisted}
      end
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
  # Orchestration helpers
  # ============================================================================

  defp run_attendance_action(%Scope{} = scope, record_id, notes, domain_fn, event_fn) do
    notes = normalize_notes(notes)

    with {:ok, record} <- fetch_record(record_id),
         {:ok, _role} <- authorize_for_record(scope, record),
         {:ok, updated} <- domain_fn.(record, scope.user.id, notes),
         # Every verb logs its transition, so there is no condition here to get
         # wrong and a new verb is covered by using this path (#1329).
         transition = AttendanceTransition.between(record, updated, scope.user.id, notes),
         {:ok, {persisted, events}} <- update_record_with_event(updated, event_fn, transition) do
      Notifications.notify_all(events)
      {:ok, persisted}
    end
  end

  @doc """
  The single ADR-0017 guard for anything hanging off a participation record.

  Public because `SessionNotes.submit_session_note/2` asks the same question: a
  note about a child at a session is authorized by that session, on the same
  provider -> staff -> admin fall-through as the child's attendance. One guard,
  two callers -- not two guards.

  The record names its session, and the session is what a role is authorized
  against. Fetched here rather than in the authorizer so that module stays free
  of this context's own tables.
  """
  @spec authorize_for_record(Scope.t(), ParticipationRecord.t()) ::
          {:ok, SessionAuthorization.role()} | {:error, :unauthorized}
  def authorize_for_record(%Scope{} = scope, %ParticipationRecord{} = record) do
    with {:ok, session} <- Sessions.get_session(record.session_id) do
      SessionAuthorization.authorize(scope, session)
    end
  end

  defp resolve_session_best_effort(session_id) do
    case Sessions.get_session(session_id) do
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

  @doc """
  Sweeps a session's still-`registered` children to `absent`, returning the
  events that describes.

  Opens no transaction of its own: the caller supplies one, because this is half
  of completing a session and the session row is the other half. A completed
  session whose registered children were never marked absent is a half-finished
  write.
  """
  @spec mark_roster_absent_for_session(ProgramSession.t()) :: {:ok, [struct()]}
  def mark_roster_absent_for_session(session) do
    registered =
      session.id
      |> list_records_by_session()
      |> Enum.filter(&(&1.status == :registered))

    {:ok, _count} = mark_records_absent(Enum.map(registered, & &1.id))
    {:ok, _logged} = log_batch_absences(registered)

    events =
      Enum.map(registered, &Events.child_marked_absent(%{&1 | status: :absent}, session))

    {:ok, events}
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

  # Why each currently-absent child is absent, in one query for the whole roster
  # rather than one per row. Only the latest `:absent` transition counts — a child
  # marked absent, checked in late, then absented again should show the second
  # reason, not the first.
  @doc """
  The most recent absence reason per record id, for the records given.

  Public for the roster reads, which show why a child was marked absent.
  """
  @spec absence_reasons_for_records([ParticipationRecord.t()]) :: %{optional(String.t()) => String.t()}
  def absence_reasons_for_records(records) do
    absent_ids = for %{status: :absent, id: id} <- records, do: id

    if absent_ids == [] do
      %{}
    else
      AttendanceTransition
      |> where([t], t.record_id in ^absent_ids and t.to_status == :absent)
      |> distinct([t], t.record_id)
      |> order_by([t], asc: t.record_id, desc: t.occurred_at, desc: t.inserted_at)
      |> select([t], {t.record_id, t.reason})
      |> Repo.all()
      |> Map.new()
    end
  end

  # `previous_status` is read off the record as it was *before* `admin_correct/2`,
  # and has to be: the corrected struct no longer knows where it came from, and the
  # row is about to stop knowing too.
  # The one attendance write that does not ride `run_attendance_action/5`, so it
  # logs its own transition. Keeping the two in step is a live obligation, not a
  # one-off — a correction missing from the log is a hole exactly where someone
  # would look for it (#1329).
  defp correct_record_with_event(record, corrected, actor_id, reason) do
    Outbox.transact_with_events(@context, fn ->
      with {:ok, persisted} <- update_record(corrected),
           :ok <- insert_transition(AttendanceTransition.between(record, persisted, actor_id, reason)) do
        session = resolve_session_best_effort(persisted.session_id)
        {:ok, persisted, [Events.attendance_corrected(persisted, session, record.status)]}
      end
    end)
  end

  defp update_record_with_event(updated, event_fn, transition) do
    Outbox.transact_with_events(@context, fn ->
      with {:ok, persisted} <- update_record(updated),
           :ok <- insert_transition(transition) do
        # Best-effort: attendance already succeeded; a session fetch failure enriches
        # the event less, it does not fail the write.
        session = resolve_session_best_effort(persisted.session_id)
        {:ok, persisted, [event_fn.(persisted, session)]}
      end
    end)
  end

  # Seeds one session's roster and stages its roster_seeded event in the same
  # transaction, so a seeded row can never exist without the event describing it.
  defp seed_roster_records(session_id, program_id, child_ids) do
    Outbox.transact_with_events(@context, fn ->
      {:ok, count} = seed_records(session_id, child_ids)
      {:ok, count, [Events.roster_seeded(session_id, program_id, count)]}
    end)
  end

  # ============================================================================
  # Persistence — participation records
  # ============================================================================

  defp fetch_record(id) when is_binary(id) do
    RepositoryHelpers.get_schema_by_uuid(ParticipationRecord, id)
  end

  defp update_record(%ParticipationRecord{} = record) do
    with {:ok, schema} <- RepositoryHelpers.get_schema_by_uuid(ParticipationRecord, record.id) do
      attrs = Map.take(record, @record_update_fields)

      schema
      |> ParticipationRecord.update_changeset(attrs)
      |> Repo.update()
      |> handle_record_update()
    end
  rescue
    Ecto.StaleEntryError -> {:error, :stale_data}
  end

  @doc """
  A session's roster rows, newest first.

  Public for the roster reads that still render a session with its children.
  """
  @spec list_records_by_session(String.t()) :: [ParticipationRecord.t()]
  def list_records_by_session(session_id) do
    ParticipationQueries.base()
    |> ParticipationQueries.by_session(session_id)
    |> ParticipationQueries.order_by_inserted_desc()
    |> Repo.all()
  end

  defp list_records_by_child(child_id) do
    ParticipationQueries.base()
    |> ParticipationQueries.by_child(child_id)
    |> ParticipationQueries.preload_session()
    |> ParticipationQueries.order_by_inserted_desc()
    |> Repo.all()
  end

  defp list_records_by_child_and_date_range(child_id, start_date, end_date) do
    ParticipationQueries.base()
    |> ParticipationQueries.by_child(child_id)
    |> ParticipationQueries.by_date_range(start_date, end_date)
    |> ParticipationQueries.order_by_session_date_desc()
    |> Repo.all()
  end

  defp list_records_by_children(child_ids) do
    ParticipationQueries.base()
    |> ParticipationQueries.by_children(child_ids)
    |> ParticipationQueries.preload_session()
    |> ParticipationQueries.order_by_inserted_desc()
    |> Repo.all()
  end

  defp list_records_by_children_and_date_range(child_ids, start_date, end_date) do
    ParticipationQueries.base()
    |> ParticipationQueries.by_children(child_ids)
    |> ParticipationQueries.by_date_range(start_date, end_date)
    |> ParticipationQueries.order_by_session_date_desc()
    |> Repo.all()
  end

  # `Repo.insert/1` answers with a changeset on failure, but every attendance verb's
  # `@spec` promises `{:error, atom()}` to its callers. `between/4` fills all four
  # required fields from two valid records, so this cannot fail on validation — a
  # failure here is the database refusing the row, and it stays an atom either way.
  defp insert_transition(transition) do
    case Repo.insert(transition) do
      {:ok, _transition} -> :ok
      {:error, %Ecto.Changeset{}} -> {:error, :transition_log_failed}
    end
  end

  # The sweep is a bulk `update_all`, so its log entries are a bulk `insert_all` —
  # neither goes through a changeset, and `insert_all` autogenerates nothing, so
  # ids and timestamps are set here. NULL actor and reason are the record of the
  # fact that nobody decided these child by child (#1329).
  defp log_batch_absences([]), do: {:ok, 0}

  defp log_batch_absences(records) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      for record <- records do
        %{
          id: Ecto.UUID.generate(),
          record_id: record.id,
          from_status: :registered,
          to_status: :absent,
          actor_id: nil,
          reason: nil,
          occurred_at: now,
          inserted_at: now,
          updated_at: now
        }
      end

    {count, _} = Repo.insert_all(AttendanceTransition, rows)
    {:ok, count}
  end

  defp mark_records_absent([]), do: {:ok, 0}

  defp mark_records_absent(record_ids) when is_list(record_ids) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {count, _} =
      from(r in ParticipationRecord, where: r.id in ^record_ids and r.status == :registered)
      |> Repo.update_all(inc: [lock_version: 1], set: [status: :absent, updated_at: now])

    {:ok, count}
  end

  defp seed_child_records([], _child_id), do: {:ok, []}

  # Returns the ids of sessions that actually gained a row: with `on_conflict:
  # :nothing`, Postgres RETURNING reports only rows that landed, so a child
  # already on a roster is skipped silently rather than double-counted.
  defp seed_child_records(session_ids, child_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      Enum.map(session_ids, fn session_id ->
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

    {_count, inserted} =
      Repo.insert_all(ParticipationRecord, rows,
        on_conflict: :nothing,
        conflict_target: [:session_id, :child_id],
        returning: [:session_id]
      )

    {:ok, Enum.map(inserted, & &1.session_id)}
  end

  defp seed_records(_session_id, []), do: {:ok, 0}

  defp seed_records(session_id, child_ids) when is_binary(session_id) and is_list(child_ids) do
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

  defp handle_record_update({:ok, schema}), do: {:ok, schema}

  defp handle_record_update({:error, %Ecto.Changeset{} = changeset}) do
    if changeset.errors[:lock_version] do
      {:error, :stale_data}
    else
      {:error, ErrorIds.participation_record_update_failed(changeset)}
    end
  end

  # Duplicated rather than shared with `SessionNotes`: six lines of pure trimming
  # with no invariant to drift, and a module existing only to hold it would be
  # the `helpers/` catch-all the layout rules reject.
  defp normalize_notes(nil), do: nil

  defp normalize_notes(notes) when is_binary(notes) do
    case String.trim(notes) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
