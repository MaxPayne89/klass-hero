defmodule KlassHero.Participation.Sessions do
  @moduledoc """
  Sessions: the lifecycle of a `ProgramSession` and every read over it.

  Owns creating, starting and editing a session, the generated-schedule
  reconciliation that keeps a program's sessions in step with its recurrence,
  and the queries the provider, staff and admin surfaces render. Completing a
  session is deliberately not here — it also sweeps the roster, so it lives in
  `CompleteSession`, one transaction across two entities.

  Callers outside the context reach these through `KlassHero.Participation`.
  Inside it, `Attendance` and `SessionNotes` call `get_session/1` for the
  session a record or note hangs off.

  State-changing operations open a `context_span`; reads stay bare.
  """

  use KlassHero.Shared.Tracing

  import Ecto.Query

  alias KlassHero.Accounts.Scope
  alias KlassHero.Participation.Attendance
  alias KlassHero.Participation.ChildInfoResolver
  alias KlassHero.Participation.Events
  alias KlassHero.Participation.Notifications
  alias KlassHero.Participation.ParticipationRecord
  alias KlassHero.Participation.ProgramSession
  alias KlassHero.Participation.SessionAuthorization
  alias KlassHero.Participation.SessionNotes
  alias KlassHero.ProgramCatalog
  alias KlassHero.Provider
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.EctoErrorHelpers
  alias KlassHero.Shared.Adapters.Driven.Persistence.RepositoryHelpers
  alias KlassHero.Shared.ErrorIds
  alias KlassHero.Shared.Outbox

  @context KlassHero.Participation

  @doc """
  Schedules a new session on `params.program_id`, on behalf of `scope`.

  Required params: `program_id`, `session_date`, `start_time`, `end_time`.

  Gated like `start_session/2` and `CompleteSession.execute/2`, and for the same
  reason (#1373, ADR-0019): this took bare params until #1074, with the ownership
  check spelled out in `SessionsLive` as a `provider_program_ids` MapSet test. A
  second create surface in Program Inventory would have been a second copy of that
  rule, and a rule respelled per surface is one a surface eventually omits.

  Authorization runs before validation, so a caller with no standing on the
  program learns nothing about whether their params would have been accepted.

  Returns `{:ok, session}`, `{:error, :unauthorized}`, `{:error, :invalid_time_range}`,
  or `{:error, :duplicate_session}`.
  """
  @spec create_session(Scope.t(), map()) ::
          {:ok, ProgramSession.t()} | {:error, :unauthorized | :invalid_time_range | :duplicate_session}
  def create_session(%Scope{} = scope, params) when is_map(params) do
    context_span entity: "session" do
      session_attrs =
        params
        |> Map.put(:id, Ecto.UUID.generate())
        |> Map.put(:status, :scheduled)

      with {:ok, _role} <- authorize_creation(scope, params),
           {:ok, session} <- ProgramSession.new(session_attrs),
           {:ok, {persisted, events}} <- insert_session_with_event(session) do
        Notifications.notify_all(events)
        {:ok, persisted}
      end
    end
  end

  # A missing program_id can never be owned, so it refuses here rather than
  # reaching the changeset's `validate_required` — same reasoning as above.
  defp authorize_creation(scope, %{program_id: program_id}) when is_binary(program_id),
    do: SessionAuthorization.authorize_creation(scope, program_id)

  defp authorize_creation(_scope, _params), do: {:error, :unauthorized}

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
          Outbox.transact_with_events(@context, fn ->
            revived = revive_generated_sessions(program, upcoming)
            inserted = insert_generated_sessions(program, upcoming)
            align_generated_capacity(program, upcoming)
            cancelled = cancel_orphaned_sessions(program, upcoming, today)

            events =
              sessions_generated_events(program_id, inserted) ++
                Enum.map(cancelled, &Events.session_cancelled/1)

            {:ok, {inserted, cancelled, revived}, events}
          end)

        # Same-context handlers only; cross-context delivery committed with the writes above.
        Notifications.notify_all(events)

        {:ok, %{generated: length(inserted), cancelled: length(cancelled), revived: revived}}
      end
    end
  end

  @doc """
  Starts a scheduled session on behalf of `scope`.

  Gated like `complete_session/2` and for the same reason (#1373): both took a
  bare session id until the guard moved here.

  Returns `{:ok, session}`, `{:error, :not_found}`, `{:error, :unauthorized}`,
  `{:error, :program_closed}`, or `{:error, :invalid_status_transition}`.
  """
  @spec start_session(Scope.t(), String.t()) ::
          {:ok, ProgramSession.t()} | {:error, :not_found | SessionAuthorization.refusal() | :invalid_status_transition}
  def start_session(%Scope{} = scope, session_id) when is_binary(session_id) do
    context_span entity: "session" do
      with {:ok, session} <- fetch_session(session_id),
           {:ok, _role} <- SessionAuthorization.authorize_lifecycle(scope, session),
           {:ok, started} <- ProgramSession.start(session),
           {:ok, {persisted, events}} <- update_session_with_event(started, &Events.session_started/1) do
        Notifications.notify_all(events)
        {:ok, persisted}
      end
    end
  end

  @doc """
  Edits an existing session on behalf of `scope`.

  Accepts `session_date`, `start_time`, `end_time`, `location`, `notes` and
  `max_capacity`. Before #1074 none of this was possible: there was no command,
  and `update_changeset/2` could not cast a date or a time, so a session typed
  with the wrong hour stayed wrong.

  **The schedule freezes once the session leaves `:scheduled`.** Attendance
  records are keyed to the session, so moving a completed one rewrites history
  its roster cannot follow. Details stay editable at every status — a wrong
  location on a session that already ran is still worth fixing. A schedule key
  submitted with its current value is not a change, so re-submitting an unchanged
  form is allowed rather than refused on the shape of the params.

  Staff are refused even when assigned, matching `create_session/2`: assignment is
  permission to run a session, not to move it.

  Returns `{:ok, session}`, `{:error, :not_found}`, `{:error, :unauthorized}`,
  `{:error, :session_started}`, `{:error, :invalid_time_range}`, or
  `{:error, :duplicate_session}`.
  """
  @spec update_session(Scope.t(), String.t(), map()) ::
          {:ok, ProgramSession.t()}
          | {:error, :not_found | :unauthorized | :session_started | :invalid_time_range | :duplicate_session}
  def update_session(%Scope{} = scope, session_id, attrs) when is_binary(session_id) and is_map(attrs) do
    context_span entity: "session" do
      with {:ok, session} <- fetch_session(session_id),
           {:ok, _role} <- authorize_session_edit(scope, session),
           :ok <- allow_schedule_change?(session, attrs),
           {:ok, {persisted, events}} <- persist_session_update(session, attrs) do
        Notifications.notify_all(events)
        {:ok, persisted}
      end
    end
  end

  # `authorize_lifecycle/2` grants :staff on an assigned session; editing does not.
  defp authorize_session_edit(scope, session) do
    case SessionAuthorization.authorize_lifecycle(scope, session) do
      {:ok, :staff} -> {:error, :unauthorized}
      {:ok, role} -> {:ok, role}
      {:error, _reason} -> {:error, :unauthorized}
    end
  end

  @schedule_fields [:session_date, :start_time, :end_time]

  defp allow_schedule_change?(%ProgramSession{status: :scheduled}, _attrs), do: :ok

  defp allow_schedule_change?(%ProgramSession{} = session, attrs) do
    changed? = Enum.any?(@schedule_fields, &(Map.has_key?(attrs, &1) and Map.get(attrs, &1) != Map.get(session, &1)))

    if changed?, do: {:error, :session_started}, else: :ok
  end

  defp persist_session_update(session, attrs) do
    Outbox.transact_with_events(@context, fn ->
      session
      |> ProgramSession.update_changeset(attrs)
      |> mark_capacity_explicit(attrs)
      |> Repo.update()
      |> case do
        {:ok, persisted} -> {:ok, persisted, [Events.session_updated(persisted)]}
        {:error, changeset} -> {:error, update_refusal(changeset)}
      end
    end)
  end

  # A caller who names a capacity has decided this one date's number, so the
  # generation sweep must stop maintaining it. Set here rather than cast, so the
  # marker records what the write meant and cannot be forged from form params.
  #
  # Keyed on the attrs the caller supplied, not on whether the value changed:
  # re-submitting the same number the program happens to dictate is still a
  # provider claiming that date, and must survive a later change to the default.
  defp mark_capacity_explicit(changeset, attrs) do
    if Map.has_key?(attrs, :max_capacity) or Map.has_key?(attrs, "max_capacity") do
      Ecto.Changeset.put_change(changeset, :capacity_source, :explicit)
    else
      changeset
    end
  end

  defp update_refusal(%Ecto.Changeset{errors: errors}) do
    cond do
      Keyword.has_key?(errors, :program_id) -> :duplicate_session
      Keyword.has_key?(errors, :end_time) -> :invalid_time_range
      true -> :invalid_session
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

  @doc """
  Counts completed sessions across the given programs.

  Aggregates over Participation's own `program_sessions` and nothing else — a
  caller holding a `provider_id` resolves it to program ids through
  `ProgramCatalog.list_program_ids_for_provider/1` first, the same two-step
  `resolve_provider_scope/1` already uses. That keeps the provider→program
  relationship in the context that owns it rather than joining across schemas.
  """
  @spec count_completed_sessions([String.t()]) :: non_neg_integer()
  def count_completed_sessions([]), do: 0

  def count_completed_sessions(program_ids) when is_list(program_ids) do
    ProgramSession
    |> where([s], s.program_id in ^program_ids and s.status == :completed)
    |> select([s], count(s.id))
    |> Repo.one()
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
      checked_in_count:
        count(fragment("CASE WHEN ? = ANY(?) THEN 1 END", pr.status, ^ParticipationRecord.checked_in_statuses())),
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
  Retrieves one session, without its roster.

  The cheap read for callers that only need the session's own facts — chiefly
  Provider, resolving a session's `program_id` to check ownership before a
  session-staffing write. `get_session_with_roster/1` answers the same question but
  loads every participation record and resolves child info across two contexts to
  do it, which is far more than a tenancy check needs.

  Returns `{:ok, %ProgramSession{}}` or `{:error, :not_found}`.
  """
  @spec get_session(String.t()) :: {:ok, ProgramSession.t()} | {:error, :not_found}
  def get_session(session_id) when is_binary(session_id), do: fetch_session(session_id)

  @doc """
  Batch sibling of `get_session/1` — the sessions matching `session_ids`.

  Unknown ids are omitted rather than reported: the callers are list views
  resolving many sessions at once, for which a missing row is a row to skip, not
  an error to propagate. Exists so those callers don't N+1 `get_session/1`.
  """
  @spec get_sessions([String.t()]) :: [ProgramSession.t()]
  def get_sessions([]), do: []

  def get_sessions(session_ids) when is_list(session_ids) do
    Repo.all(from s in ProgramSession, where: s.id in ^session_ids)
  end

  @doc "Returns the list of valid session statuses."
  def session_statuses, do: ProgramSession.valid_statuses()

  defp insert_session_with_event(session) do
    Outbox.transact_with_events(@context, fn ->
      with {:ok, persisted} <- insert_session(session) do
        {:ok, persisted, [Events.session_created(persisted)]}
      end
    end)
  end

  defp update_session_with_event(session, event_fn) do
    Outbox.transact_with_events(@context, fn ->
      with {:ok, persisted} <- update_session(session) do
        {:ok, persisted, [event_fn.(persisted)]}
      end
    end)
  end

  defp sessions_generated_events(_program_id, []), do: []

  defp sessions_generated_events(program_id, sessions) do
    [Events.sessions_generated(program_id, sessions)]
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

  # `get_schema_by_uuid/2` rather than a bare `Repo.get/2`: this id comes from the
  # client, and a value that cannot be cast to a UUID raises against a binary_id
  # column instead of refusing (#1478).
  @doc """
  Persists a lifecycle transition already applied to `session` in memory.

  Public because completing a session is not this module's to own — the write
  and the roster sweep it implies belong in one transaction, which
  `CompleteSession` opens. It supplies the transaction; this supplies the
  session half of the write.
  """
  @spec persist_lifecycle_update(ProgramSession.t()) :: {:ok, ProgramSession.t()} | {:error, atom()}
  def persist_lifecycle_update(%ProgramSession{} = session), do: update_session(session)

  @doc """
  The ids of a program's still-scheduled sessions from today forward.

  Public for `Attendance.backfill_roster_for_enrollment/2`, which seeds a late
  enrollee onto exactly these.
  """
  @spec upcoming_scheduled_session_ids(String.t()) :: [String.t()]
  def upcoming_scheduled_session_ids(program_id) when is_binary(program_id), do: upcoming_scheduled_ids(program_id)

  defp fetch_session(id) when is_binary(id) do
    RepositoryHelpers.get_schema_by_uuid(ProgramSession, id)
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

  # Capacity is realigned, not merely seeded at insert. `insert_generated_sessions/2`
  # uses `on_conflict: :nothing`, so a value copied at creation is frozen — a provider
  # raising their capacity would see every existing date keep the old number, which is
  # how `location` behaves today and is a latent bug there.
  #
  # What it must not touch is a capacity a human chose. A provider can open one
  # generated date and give it its own number (`ParticipationLive` ->
  # `update_session/3`), which stamps `capacity_source: :explicit`; only `:inherited`
  # rows are swept. `origin` cannot carry this distinction — it says where the
  # *session* came from, and both kinds of capacity sit on `origin: :generated` rows.
  #
  # Scoped through `generated_slot_query/1` so "still a valid slot" means the same
  # here as in `cancel_orphaned_sessions/3`: a row left at a superseded start time is
  # about to be cancelled, and realigning it first would be a write to a dead row.
  # A session already started, finished or cancelled keeps whatever it ran with.
  #
  # Stages no event: no read table carries `max_capacity`, so there is no projection
  # for this write to drift from.
  defp align_generated_capacity(_program, []), do: :ok

  defp align_generated_capacity(%{default_session_capacity: nil} = program, dates) do
    program
    |> realignable_sessions(dates)
    |> where([s], not is_nil(s.max_capacity))
    |> Repo.update_all(set: [max_capacity: nil, updated_at: now_utc()])

    :ok
  end

  defp align_generated_capacity(%{default_session_capacity: capacity} = program, dates) do
    program
    |> realignable_sessions(dates)
    |> where([s], is_nil(s.max_capacity) or s.max_capacity != ^capacity)
    |> Repo.update_all(set: [max_capacity: capacity, updated_at: now_utc()])

    :ok
  end

  # Split on the nil default rather than comparing in one expression: Ecto refuses
  # `s.max_capacity != ^nil`, because in SQL that is NULL rather than true and would
  # silently match nothing.
  defp realignable_sessions(program, dates) do
    program
    |> generated_slot_query()
    |> where([s], s.status == :scheduled)
    |> where([s], s.session_date in ^dates)
    |> where([s], s.capacity_source == :inherited)
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
          max_capacity: program.default_session_capacity,
          capacity_source: :inherited,
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

  defp upcoming_scheduled_ids(program_id) do
    today = Date.utc_today()

    from(s in ProgramSession,
      where: s.program_id == ^program_id and s.status == :scheduled and s.session_date >= ^today,
      select: s.id
    )
    |> Repo.all()
  end

  @doc """
  Retrieves a session with its complete roster.

  Returns `{:ok, %{session: session, roster: roster}}` or `{:error, :not_found}`.
  """
  def get_session_with_roster(session_id) when is_binary(session_id) do
    with {:ok, session} <- fetch_session(session_id) do
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
    with {:ok, session} <- fetch_session(session_id) do
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
        |> Map.put(:program_name, fetch_program_name(session.program_id))

      {:ok, enriched_session}
    end
  end

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
end
