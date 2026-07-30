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

  alias KlassHero.Participation.Adapters.Driven.ACL.ChildInfoResolver
  alias KlassHero.Participation.Adapters.Driven.ACL.EnrolledChildrenResolver
  alias KlassHero.Participation.Adapters.Driven.ACL.ProgramProviderResolver
  alias KlassHero.Participation.Adapters.Driven.Persistence.Queries.ParticipationQueries
  alias KlassHero.Participation.Adapters.Driven.Persistence.Queries.SessionNoteQueries
  alias KlassHero.Participation.Adapters.Driving.Events.EventHandlers.NotifyLiveViews
  alias KlassHero.Participation.Domain.Events.ParticipationEvents
  alias KlassHero.Participation.ParticipationRecord
  alias KlassHero.Participation.ProgramSession
  alias KlassHero.Participation.SessionNote
  alias KlassHero.ProgramCatalog
  alias KlassHero.Provider
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.EctoErrorHelpers
  alias KlassHero.Shared.Adapters.Driven.Persistence.RepositoryHelpers
  alias KlassHero.Shared.DomainEventBus
  alias KlassHero.Shared.ErrorIds
  alias KlassHero.Shared.Outbox

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
    context_span entity: "session" do
      session_attrs =
        params
        |> Map.put(:id, Ecto.UUID.generate())
        |> Map.put(:status, :scheduled)

      with {:ok, session} <- ProgramSession.new(session_attrs),
           {:ok, {persisted, events}} <-
             Outbox.transact(@context, fn ->
               with {:ok, persisted} <- insert_session(session) do
                 {:ok, persisted, [ParticipationEvents.session_created(persisted)]}
               end
             end) do
        dispatch_all(events)
        {:ok, persisted}
      end
    end
  end

  @doc """
  Brings a program's generated sessions into agreement with its recurring schedule.

  Idempotent, and deliberately so: `program_updated` carries a full snapshot
  rather than a diff, so a caller cannot tell a schedule edit from a title edit
  and must be safe to run on every write.

  Three steps, all scoped to `origin: :generated` sessions dated today or later:
  slots that returned to the schedule are revived, missing ones are created, and
  ones that fell out are cancelled. Manually created sessions are never touched,
  and neither is any session already started, completed or cancelled.

  Returns `{:error, :incomplete_schedule}` when the program has no full schedule
  to derive from — distinct from a complete schedule that yields no dates.
  """
  @spec sync_sessions_for_program(String.t()) ::
          {:ok, %{generated: non_neg_integer(), cancelled: non_neg_integer(), revived: non_neg_integer()}}
          | {:error, :program_not_found | :incomplete_schedule | :schedule_range_too_large}
  def sync_sessions_for_program(program_id) when is_binary(program_id) do
    context_span entity: "session" do
      with {:ok, program} <- fetch_program_for_sync(program_id),
           {:ok, dates} <- ProgramCatalog.meeting_dates(program) do
        today = Date.utc_today()
        upcoming = Enum.reject(dates, &Date.before?(&1, today))

        {:ok, {{inserted, cancelled, revived}, events}} =
          Outbox.transact(@context, fn ->
            revived = revive_generated_sessions(program, upcoming)
            inserted = insert_generated_sessions(program, upcoming)
            cancelled = cancel_orphaned_sessions(program, upcoming, today)

            events =
              sessions_generated_events(program_id, inserted) ++
                Enum.map(cancelled, &ParticipationEvents.session_cancelled/1)

            {:ok, {inserted, cancelled, revived}, events}
          end)

        # Same-context handlers only; cross-context delivery committed with the writes above.
        dispatch_all(events)

        {:ok, %{generated: length(inserted), cancelled: length(cancelled), revived: revived}}
      end
    end
  end

  @doc """
  Starts a scheduled session.

  Returns `{:ok, session}`, `{:error, :not_found}`, or `{:error, :invalid_status_transition}`.
  """
  def start_session(session_id) when is_binary(session_id) do
    context_span entity: "session" do
      with {:ok, session} <- fetch_session(session_id),
           {:ok, started} <- ProgramSession.start(session),
           {:ok, {persisted, events}} <-
             Outbox.transact(@context, fn ->
               with {:ok, persisted} <- update_session(started) do
                 {:ok, persisted, [ParticipationEvents.session_started(persisted)]}
               end
             end) do
        dispatch_all(events)
        {:ok, persisted}
      end
    end
  end

  @doc """
  Completes an in-progress session, marking all registered (not checked-in) children as absent.

  Returns `{:ok, session}`, `{:error, :not_found}`, or `{:error, :invalid_status_transition}`.
  """
  def complete_session(session_id) when is_binary(session_id) do
    context_span entity: "session" do
      with {:ok, session} <- fetch_session(session_id),
           {:ok, completed} <- ProgramSession.complete(session),
           {:ok, {persisted, events}} <-
             Outbox.transact(@context, fn ->
               with {:ok, persisted} <- update_session(completed),
                    {:ok, absence_events} <- mark_remaining_as_absent(persisted) do
                 {:ok, persisted, absence_events ++ [session_completed_event(persisted)]}
               end
             end) do
        dispatch_all(events)
        {:ok, persisted}
      end
    end
  end

  @doc "Lists sessions, optionally filtered by `program_id` or `date`."
  def list_sessions(params \\ %{})

  def list_sessions(%{program_id: program_id}) when is_binary(program_id), do: list_sessions_by_program(program_id)

  def list_sessions(%{date: %Date{} = date}), do: list_sessions_today(date)
  def list_sessions(params) when is_map(params), do: list_sessions_today(Date.utc_today())

  @doc "Lists sessions on or after `from_date` across many programs in one query, ordered soonest-first."
  @spec list_upcoming_sessions_for_programs([String.t()], Date.t()) :: [ProgramSession.t()]
  def list_upcoming_sessions_for_programs(program_ids, %Date{} = from_date) when is_list(program_ids) do
    from(s in ProgramSession,
      where: s.program_id in ^program_ids and s.session_date >= ^from_date,
      order_by: [asc: s.session_date, asc: s.start_time]
    )
    |> Repo.all()
  end

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

    filters
    |> resolve_provider_scope()
    |> aggregate_admin_sessions()
    |> enrich_session_names()
  end

  @doc "Lists sessions for a provider on a specific date (defaults to today)."
  def list_provider_sessions(provider_id, date \\ nil) when is_binary(provider_id) do
    date = date || Date.utc_today()

    case ProgramCatalog.list_program_ids_for_provider(provider_id) do
      [] ->
        {:ok, []}

      program_ids ->
        sessions =
          from(s in ProgramSession,
            where: s.program_id in ^program_ids and s.session_date == ^date,
            order_by: [asc: s.start_time]
          )
          |> Repo.all()

        {:ok, sessions}
    end
  end

  # Statuses that count toward the attendance tally ("has attended", not "currently present").
  @admin_checked_in_statuses ~w(checked_in checked_out)

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
        count(fragment("CASE WHEN ? = ANY(?) THEN 1 END", r.status, ^@admin_checked_in_statuses))
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
      checked_in: Enum.count(records, &("#{&1.status}" in @admin_checked_in_statuses))
    }
  end

  # Translate a cross-context :provider_id filter into a local :program_ids filter,
  # so the aggregation query stays free of ProgramCatalog/Provider vocabulary.
  defp resolve_provider_scope(%{provider_id: provider_id} = filters) do
    program_ids = ProgramCatalog.list_program_ids_for_provider(provider_id)

    filters
    |> Map.delete(:provider_id)
    |> Map.put(:program_ids, program_ids)
  end

  defp resolve_provider_scope(filters), do: filters

  # Local aggregation over Participation-owned tables only; no cross-context joins.
  defp aggregate_admin_sessions(filters) do
    ProgramSession
    |> join(:left, [s], pr in ParticipationRecord, on: pr.session_id == s.id)
    |> apply_admin_filters(filters)
    |> group_by([s, _pr], s.id)
    |> select([s, pr], %{
      id: s.id,
      program_id: s.program_id,
      session_date: s.session_date,
      start_time: s.start_time,
      end_time: s.end_time,
      status: s.status,
      checked_in_count: count(fragment("CASE WHEN ? = ANY(?) THEN 1 END", pr.status, ^@admin_checked_in_statuses)),
      total_count: count(pr.id)
    })
    |> order_by([s, _pr], asc: s.session_date, asc: s.start_time)
    |> Repo.all()
    |> Enum.map(&atomize_session_status/1)
  end

  defp apply_admin_filters(query, filters) do
    query
    |> maybe_filter_date(filters)
    |> maybe_filter_date_range(filters)
    |> maybe_filter_program_ids(filters)
    |> maybe_filter_program(filters)
    |> maybe_filter_status(filters)
  end

  defp maybe_filter_date(query, %{date: date}), do: where(query, [s, _pr], s.session_date == ^date)
  defp maybe_filter_date(query, _), do: query

  defp maybe_filter_date_range(query, %{date_from: from, date_to: to}),
    do: where(query, [s, _pr], s.session_date >= ^from and s.session_date <= ^to)

  defp maybe_filter_date_range(query, _), do: query

  defp maybe_filter_program_ids(query, %{program_ids: ids}), do: where(query, [s, _pr], s.program_id in ^ids)

  defp maybe_filter_program_ids(query, _), do: query

  defp maybe_filter_program(query, %{program_id: id}), do: where(query, [s, _pr], s.program_id == type(^id, Ecto.UUID))

  defp maybe_filter_program(query, _), do: query

  defp maybe_filter_status(query, %{status: status}), do: where(query, [s, _pr], s.status == ^status)

  defp maybe_filter_status(query, _), do: query

  # Ecto map-`select` returns the enum column as its raw DB string; coerce back to an atom
  # so consumers (the LiveView) pattern-match on atoms as before.
  defp atomize_session_status(%{status: status} = row) when is_binary(status),
    do: %{row | status: String.to_existing_atom(status)}

  defp atomize_session_status(row), do: row

  # Single program title via the owning context's facade; nil when the program is absent
  # (preserves the prior Repo.one-returns-nil behaviour).
  defp fetch_program_name(program_id) do
    case ProgramCatalog.get_program_by_id(program_id) do
      {:ok, program} -> program.title
      {:error, :not_found} -> nil
    end
  end

  # Batch-resolve program titles + provider names through the owning contexts' facades.
  # Fixed 2 extra queries regardless of row count (keyed on distinct ids).
  defp enrich_session_names(rows) do
    program_facts =
      rows
      |> Enum.map(& &1.program_id)
      |> Enum.uniq()
      |> ProgramCatalog.get_programs_by_ids()
      |> Map.new(&{&1.id, {&1.title, &1.provider_id}})

    provider_names =
      program_facts
      |> Map.values()
      |> Enum.map(fn {_title, provider_id} -> provider_id end)
      |> Enum.uniq()
      |> Provider.get_business_names()

    Enum.map(rows, fn row ->
      {title, provider_id} = Map.get(program_facts, row.program_id, {nil, nil})

      Map.merge(row, %{
        program_name: title,
        provider_name: Map.get(provider_names, provider_id)
      })
    end)
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
        |> Map.put(:program_name, fetch_program_name(session.program_id))

      {:ok, enriched_session}
    end
  end

  @doc "Returns the list of valid session statuses."
  def session_statuses, do: ProgramSession.valid_statuses()

  @doc """
  Returns the PubSub topics a LiveView should subscribe to for a subscription
  group (`:session_note` or `:attendance`).

  Topics derive from `ParticipationEvents`' event registry (#1108), so renaming an
  event atom moves the publisher and every subscriber together — no hand-typed
  topic strings in LiveViews.
  """
  @spec participation_topics(atom()) :: [String.t()]
  def participation_topics(group) do
    for event_type <- ParticipationEvents.subscription_event_types(group), do: event_topic(event_type)
  end

  @doc "Returns the PubSub topic a single event type is published on."
  @spec event_topic(atom()) :: String.t()
  def event_topic(event_type) do
    NotifyLiveViews.build_topic(ParticipationEvents.aggregate_type_for(event_type), event_type)
  end

  @doc """
  Returns the provider-scoped participation topic — the single topic carrying all
  of a provider's participation events. Provider/staff LiveViews subscribe to it;
  `NotifyLiveViews` publishes to it. One builder, so the two sides can't drift.
  """
  @spec provider_topic(String.t()) :: String.t()
  defdelegate provider_topic(provider_id), to: NotifyLiveViews

  @doc """
  Returns the child-scoped participation topic — the single topic carrying one
  child's attendance and session-note events. Parent LiveViews subscribe to it
  per child; `NotifyLiveViews` publishes to it. One builder, so the two sides
  can't drift (#1121).
  """
  @spec child_topic(String.t()) :: String.t()
  defdelegate child_topic(child_id), to: NotifyLiveViews

  @doc """
  Seeds a session roster with the program's enrolled children. Best-effort: always returns `:ok`.

  Invoked by the `session_created` integration-event handler.
  """
  @spec seed_session_roster(String.t(), String.t()) :: :ok
  def seed_session_roster(session_id, program_id) when is_binary(session_id) and is_binary(program_id) do
    context_span entity: "participation_record" do
      child_ids = EnrolledChildrenResolver.list_enrolled_child_ids(program_id)

      # max_capacity is not checked: capacity is an enrollment-time concern, not a roster gate.
      {:ok, {count, roster_events}} = seed_roster_records(session_id, program_id, child_ids)

      Logger.info(
        "[Participation] Seeded roster — enrolled=#{length(child_ids)} inserted=#{count} skipped=#{length(child_ids) - count}",
        session_id: session_id,
        program_id: program_id
      )

      dispatch_all(roster_events)

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
      child_ids = EnrolledChildrenResolver.list_enrolled_child_ids(program_id)

      for session_id <- session_ids do
        {:ok, {_count, events}} = seed_roster_records(session_id, program_id, child_ids)
        dispatch_all(events)
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
      session_ids = upcoming_scheduled_session_ids(program_id)

      # One event per session that actually gained a row, so each session's
      # read-model count moves by exactly the number of rows it gained.
      {:ok, {seeded_ids, backfill_events}} =
        Outbox.transact(@context, fn ->
          {:ok, seeded_ids} = seed_child_records(session_ids, child_id)
          {:ok, seeded_ids, Enum.map(seeded_ids, &ParticipationEvents.roster_seeded(&1, program_id, 1))}
        end)

      Logger.info(
        "[Participation] Backfilled roster — upcoming=#{length(session_ids)} inserted=#{length(seeded_ids)}",
        child_id: child_id,
        program_id: program_id
      )

      dispatch_all(backfill_events)

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
  Checks in a child to a session.

  Required params: `record_id`, `checked_in_by`. Optional: `notes`.

  Returns `{:ok, record}`, `{:error, :not_found}`, or `{:error, :invalid_status_transition}`.
  """
  def record_check_in(%{record_id: record_id, checked_in_by: checked_in_by} = params) do
    context_span entity: "participation_record" do
      run_attendance_action(
        record_id,
        checked_in_by,
        Map.get(params, :notes),
        &ParticipationRecord.check_in/3,
        &ParticipationEvents.child_checked_in/2
      )
    end
  end

  @doc """
  Checks out a child from a session.

  Required params: `record_id`, `checked_out_by`. Optional: `notes`.

  Returns `{:ok, record}`, `{:error, :not_found}`, or `{:error, :invalid_status_transition}`.
  """
  def record_check_out(%{record_id: record_id, checked_out_by: checked_out_by} = params) do
    context_span entity: "participation_record" do
      run_attendance_action(
        record_id,
        checked_out_by,
        Map.get(params, :notes),
        &ParticipationRecord.check_out/3,
        &ParticipationEvents.child_checked_out/2
      )
    end
  end

  @doc """
  Checks in multiple children at once.

  Required params: `record_ids`, `checked_in_by`. Optional: `notes`.

  Returns a map with `successful` (records) and `failed` (`{record_id, reason}` tuples).
  """
  def bulk_check_in(%{record_ids: record_ids, checked_in_by: checked_in_by} = params) do
    context_span entity: "participation_record" do
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
  end

  @doc "Admin-corrects a participation record's attendance data."
  def correct_attendance(%{record_id: record_id} = params) do
    context_span entity: "participation_record" do
      actor_role = Map.get(params, :actor_role, :admin)

      with :ok <- validate_correction_reason(actor_role, params),
           {:ok, record} <- fetch_record(record_id),
           correction_attrs = build_correction_attrs(actor_role, record, params),
           {:ok, corrected} <- ParticipationRecord.admin_correct(record, correction_attrs) do
        update_record(corrected)
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
  # Session notes
  # ============================================================================

  @doc """
  Submits a session note for a participation record.

  Required params: `participation_record_id`, `provider_id`, `content` (max 1000 chars).
  """
  def submit_session_note(%{participation_record_id: record_id, provider_id: provider_id, content: content}) do
    context_span entity: "session_note" do
      normalized_content = normalize_notes(content)

      with {:content, content} when content != nil <- {:content, normalized_content},
           {:ok, record} <- fetch_record(record_id),
           true <- ParticipationRecord.allows_session_note?(record),
           {:ok, note} <- build_note(record, provider_id, content),
           {:ok, persisted} <- insert_note(note) do
        log_publish_result(
          DomainEventBus.dispatch(@context, ParticipationEvents.session_note_submitted(persisted)),
          persisted.id
        )

        {:ok, persisted}
      else
        {:content, nil} -> {:error, :blank_content}
        false -> {:error, :invalid_record_status}
        error -> error
      end
    end
  end

  @doc """
  Reviews a session note (approve or reject).

  Required params: `note_id`, `parent_id` (ownership enforced at DB level),
  `decision` (`:approve` or `:reject`). Optional: `reason`.
  """
  def review_session_note(%{note_id: note_id, parent_id: parent_id, decision: decision} = params) do
    context_span entity: "session_note" do
      reason = Map.get(params, :reason)

      # Scoped query enforces ownership at DB level — returns :not_found if note doesn't belong to parent.
      with {:ok, note} <- fetch_note_by_parent(note_id, parent_id),
           {:ok, reviewed} <- apply_review_decision(note, decision, reason),
           {:ok, persisted} <- update_note(reviewed) do
        log_publish_result(publish_review_event(persisted, decision), persisted.id)
        {:ok, persisted}
      end
    end
  end

  @doc """
  Revises a rejected session note with new content.

  Required params: `note_id`, `provider_id` (ownership enforced at DB level), `content`.
  """
  def revise_session_note(%{note_id: note_id, provider_id: provider_id, content: content}) do
    context_span entity: "session_note" do
      normalized_content = normalize_notes(content)

      # Scoped query enforces ownership at DB level — returns :not_found if note doesn't belong to provider.
      with {:content, content} when content != nil <- {:content, normalized_content},
           {:ok, note} <- fetch_note_by_provider(note_id, provider_id),
           {:ok, revised} <- SessionNote.revise(note, content),
           {:ok, persisted} <- update_note(revised) do
        log_publish_result(
          DomainEventBus.dispatch(@context, ParticipationEvents.session_note_submitted(persisted)),
          persisted.id
        )

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

  @doc "Lists pending session notes for a parent awaiting review."
  def list_pending_session_notes(parent_id) when is_binary(parent_id) do
    {:ok, list_notes_pending_by_parent(parent_id)}
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

  # ============================================================================
  # Orchestration helpers
  # ============================================================================

  defp run_attendance_action(record_id, actor_id, notes, domain_fn, event_fn) do
    notes = normalize_notes(notes)

    with {:ok, record} <- fetch_record(record_id),
         {:ok, updated} <- domain_fn.(record, actor_id, notes),
         {:ok, {persisted, events}} <-
           Outbox.transact(@context, fn ->
             with {:ok, persisted} <- update_record(updated) do
               # Best-effort: attendance already succeeded; a session fetch failure
               # enriches the event less, it does not fail the write.
               session = resolve_session_best_effort(nil, persisted.session_id)
               {:ok, persisted, [event_fn.(persisted, session)]}
             end
           end) do
      dispatch_all(events)
      {:ok, persisted}
    end
  end

  defp bulk_check_in_record(record_id, checked_in_by, notes, session) do
    with {:ok, record} <- fetch_record(record_id),
         {:ok, checked_in} <- ParticipationRecord.check_in(record, checked_in_by, notes),
         {:ok, {{persisted, resolved}, events}} <-
           Outbox.transact(@context, fn ->
             with {:ok, persisted} <- update_record(checked_in) do
               resolved = resolve_session_best_effort(session, persisted.session_id)
               {:ok, {persisted, resolved}, [check_in_event(persisted, resolved)]}
             end
           end) do
      dispatch_all(events)
      {:ok, persisted, resolved}
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

    events =
      Enum.map(registered, &ParticipationEvents.child_marked_absent(%{&1 | status: :absent}, session))

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

  defp build_note(record, provider_id, content) do
    SessionNote.new(%{
      id: Ecto.UUID.generate(),
      participation_record_id: record.id,
      child_id: record.child_id,
      parent_id: record.parent_id,
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
      session_notes: notes
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
    ParticipationEvents.session_completed(session, extra_payload: extra_payload)
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

  defp check_in_event(record, %ProgramSession{} = session), do: ParticipationEvents.child_checked_in(record, session)

  defp check_in_event(record, nil), do: ParticipationEvents.child_checked_in(record)

  # Seeds one session's roster and stages its roster_seeded event in the same
  # transaction, so a seeded row can never exist without the event describing it.
  defp seed_roster_records(session_id, program_id, child_ids) do
    Outbox.transact(@context, fn ->
      {:ok, count} = seed_records(session_id, child_ids)
      {:ok, count, [ParticipationEvents.roster_seeded(session_id, program_id, count)]}
    end)
  end

  defp sessions_generated_events(_program_id, []), do: []

  defp sessions_generated_events(program_id, sessions) do
    [ParticipationEvents.sessions_generated(program_id, sessions)]
  end

  # Same-context handlers still on the bus (NotifyLiveViews and the business ones).
  # Cross-context delivery already committed with the write.
  defp dispatch_all(events) do
    Enum.each(events, fn event ->
      case DomainEventBus.dispatch(@context, event) do
        :ok ->
          :ok

        {:error, failures} ->
          Logger.warning("[Participation] #{event.event_type} handler failures: #{inspect(failures)}",
            aggregate_id: event.aggregate_id
          )
      end
    end)
  end

  defp publish_review_event(note, :approve) do
    DomainEventBus.dispatch(@context, ParticipationEvents.session_note_approved(note))
  end

  defp publish_review_event(note, :reject) do
    DomainEventBus.dispatch(@context, ParticipationEvents.session_note_rejected(note))
  end

  defp log_publish_result(:ok, _id), do: :ok

  defp log_publish_result({:error, reason}, id) do
    Logger.warning("[Participation] PubSub publish failed", id: id, reason: inspect(reason))
  end

  # ============================================================================
  # Persistence — sessions
  # ============================================================================

  defp insert_session(%ProgramSession{} = session) do
    session
    |> Map.from_struct()
    |> ProgramSession.create_changeset()
    |> Repo.insert()
    |> handle_session_insert()
  end

  defp fetch_session(id) when is_binary(id) do
    case Repo.get(ProgramSession, id) do
      nil -> {:error, :not_found}
      session -> {:ok, session}
    end
  end

  defp update_session(%ProgramSession{} = session) do
    with {:ok, schema} <- RepositoryHelpers.get_schema_by_uuid(ProgramSession, session.id) do
      attrs = Map.take(session, [:status, :location, :notes, :max_capacity, :lock_version])

      schema
      |> ProgramSession.update_changeset(attrs)
      |> Repo.update()
      |> handle_session_update()
    end
  end

  defp list_sessions_by_program(program_id) do
    from(s in ProgramSession,
      where: s.program_id == ^program_id,
      order_by: [asc: s.session_date, asc: s.start_time]
    )
    |> Repo.all()
  end

  defp list_sessions_today(date) do
    from(s in ProgramSession, where: s.session_date == ^date, order_by: [asc: s.start_time])
    |> Repo.all()
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
    case Repo.get(ParticipationRecord, id) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
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

  defp list_records_by_session(session_id) do
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

  defp mark_records_absent([]), do: {:ok, 0}

  defp mark_records_absent(record_ids) when is_list(record_ids) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {count, _} =
      from(r in ParticipationRecord, where: r.id in ^record_ids and r.status == :registered)
      |> Repo.update_all(inc: [lock_version: 1], set: [status: :absent, updated_at: now])

    {:ok, count}
  end

  defp fetch_program_for_sync(program_id) do
    case ProgramCatalog.get_program_by_id(program_id) do
      {:ok, program} -> {:ok, program}
      {:error, :not_found} -> {:error, :program_not_found}
    end
  end

  # A generated session is identified by its slot — date *and* start time — so
  # moving a program's meeting time orphans the old slot rather than editing it.
  defp generated_slot_query(program) do
    from(s in ProgramSession,
      where: s.program_id == ^program.id,
      where: s.origin == :generated,
      where: s.start_time == ^program.meeting_start_time
    )
  end

  defp revive_generated_sessions(_program, []), do: 0

  # Without this a narrow-then-revert edit would silently lose those sessions:
  # the slot's row still exists, so the insert below skips it, and nothing else
  # would ever move it back off :cancelled.
  defp revive_generated_sessions(program, dates) do
    {count, _} =
      program
      |> generated_slot_query()
      |> where([s], s.status == :cancelled and s.session_date in ^dates)
      |> Repo.update_all(set: [status: :scheduled, updated_at: now_utc()])

    count
  end

  defp insert_generated_sessions(_program, []), do: []

  defp insert_generated_sessions(program, dates) do
    now = now_utc()

    rows =
      for date <- dates do
        %{
          id: Ecto.UUID.generate(),
          program_id: program.id,
          session_date: date,
          start_time: program.meeting_start_time,
          end_time: program.meeting_end_time,
          status: :scheduled,
          origin: :generated,
          location: program.location,
          lock_version: 1,
          inserted_at: now,
          updated_at: now
        }
      end

    {_count, inserted} =
      Repo.insert_all(ProgramSession, rows,
        on_conflict: :nothing,
        conflict_target: [:program_id, :session_date, :start_time],
        returning: [:id, :session_date, :start_time, :end_time]
      )

    inserted
  end

  # Only :scheduled rows are swept, so a session already under way or finished
  # keeps its outcome no matter what happens to the schedule.
  defp cancel_orphaned_sessions(program, dates, today) do
    orphans =
      from(s in ProgramSession,
        where: s.program_id == ^program.id,
        where: s.origin == :generated,
        where: s.status == :scheduled,
        where: s.session_date >= ^today,
        where: s.session_date not in ^dates or s.start_time != ^program.meeting_start_time
      )

    # `select` rather than the :returning option — update_all returns the updated
    # rows only when the query itself selects them.
    {_count, cancelled} =
      orphans
      |> select([s], s)
      |> Repo.update_all(set: [status: :cancelled, updated_at: now_utc()])

    cancelled
  end

  defp now_utc, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp upcoming_scheduled_session_ids(program_id) do
    today = Date.utc_today()

    from(s in ProgramSession,
      where: s.program_id == ^program_id and s.status == :scheduled and s.session_date >= ^today,
      select: s.id
    )
    |> Repo.all()
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

  defp list_notes_pending_by_parent(parent_id) do
    SessionNoteQueries.base()
    |> SessionNoteQueries.by_parent(parent_id)
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

  defp fetch_note_by_parent(id, parent_id) do
    SessionNoteQueries.base()
    |> SessionNoteQueries.by_parent(parent_id)
    |> where([note: n], n.id == ^id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      schema -> {:ok, schema}
    end
  end

  defp fetch_note_by_provider(id, provider_id) do
    SessionNoteQueries.base()
    |> SessionNoteQueries.by_provider(provider_id)
    |> where([note: n], n.id == ^id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      schema -> {:ok, schema}
    end
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
