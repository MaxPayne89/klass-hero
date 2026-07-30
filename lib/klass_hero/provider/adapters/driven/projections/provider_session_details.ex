defmodule KlassHero.Provider.Adapters.Driven.Projections.ProviderSessionDetails do
  @moduledoc """
  Event-driven projection maintaining the `provider_session_details` read table.

  Subscribes to Participation context integration events covering session
  lifecycle (created/started/completed/cancelled), attendance (checked in/out,
  marked absent), and roster + staff assignment changes. Maintains the
  denormalised view consumed by the provider session dashboard.

  Built on `KlassHero.Shared.Projection` (base) + `Projection.WithBootstrapRetry`
  (linear-backoff retry on transient bootstrap failure).

  ## Event handling

  - `:session_created` — upserts a row with defaults, resolving program_title,
    provider_id, and currently assigned staff from the write tables.
  - `:session_started` — sets status to `:in_progress`.
  - `:session_completed` — sets status to `:completed`.
  - `:session_cancelled` — sets status to `:cancelled`.
  - `:roster_seeded` — sets total_count from the seeded roster size.
  - `:child_checked_in` — increments checked_in_count (monotonic; not reversed).
  - `:child_checked_out` — intentional no-op (counter is monotonic).
  - `:child_marked_absent` — intentional no-op (no effect on checked_in_count).
  - `:staff_assigned_to_program` — bulk-updates current_assigned_staff_* on all
    `:scheduled` rows for the program.
  - `:staff_unassigned_from_program` — bulk-clears current_assigned_staff_* on all
    `:scheduled` rows for the program.
  """

  use KlassHero.Shared.Projection,
    topics: [
      "integration:participation:session_created",
      "integration:participation:sessions_generated",
      "integration:participation:session_started",
      "integration:participation:session_completed",
      "integration:participation:session_cancelled",
      "integration:participation:roster_seeded",
      "integration:participation:child_checked_in",
      "integration:participation:child_checked_out",
      "integration:participation:child_marked_absent",
      "integration:provider:staff_assigned_to_program",
      "integration:provider:staff_unassigned_from_program"
    ]

  use KlassHero.Shared.Projection.WithBootstrapRetry

  import Ecto.Query

  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.ProviderSessionDetailSchema
  alias KlassHero.Repo
  alias KlassHero.Shared.Domain.Events.Event
  alias KlassHero.Shared.Projection

  @impl Projection
  def bootstrap_impl, do: bootstrap_session_details()

  @impl Projection
  def handle_event(:session_created, %Event{} = event) do
    Logger.debug("ProviderSessionDetails projecting session_created",
      session_id: event.entity_id,
      event_id: event.event_id
    )

    project_session_created(event.payload)
  end

  # The batch shares one program, so its title/provider/staff resolve once here
  # rather than once per session as the per-session clause above does.
  def handle_event(:sessions_generated, %Event{payload: %{program_id: program_id, sessions: sessions}}) do
    Enum.each(sessions, &project_session_created(Map.put(&1, :program_id, program_id)))
  end

  def handle_event(:session_started, %Event{} = event) do
    update_status(event.entity_id, :in_progress)
  end

  def handle_event(:session_completed, %Event{} = event) do
    update_status(event.entity_id, :completed)
  end

  def handle_event(:session_cancelled, %Event{} = event) do
    update_status(event.entity_id, :cancelled)
  end

  # `seeded_count` is the delta a seeding inserted, not a running total — a roster
  # is seeded once at session creation and again whenever a child enrols later, so
  # this accumulates rather than overwrites.
  def handle_event(:roster_seeded, %Event{payload: %{seeded_count: seeded_count}} = event) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(d in ProviderSessionDetailSchema, where: d.session_id == ^event.entity_id)
    |> Repo.update_all(inc: [total_count: seeded_count], set: [updated_at: now])
    |> warn_if_missing("roster_seeded", session_id: event.entity_id, seeded_count: seeded_count)
  end

  # Monotonic: once counted on check-in, a child stays counted for "how many showed up".
  def handle_event(:child_checked_in, %Event{payload: %{session_id: session_id}} = event) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(d in ProviderSessionDetailSchema, where: d.session_id == ^session_id)
    |> Repo.update_all(inc: [checked_in_count: 1], set: [updated_at: now])
    |> warn_if_missing("child_checked_in", session_id: session_id, record_id: event.entity_id)
  end

  # Intentional no-op: counter is monotonic; check-outs don't reduce "how many showed up".
  def handle_event(:child_checked_out, %Event{} = event) do
    Logger.debug("ProviderSessionDetails ignoring child_checked_out (counter is monotonic)",
      record_id: event.entity_id
    )
  end

  # Intentional no-op: absences are the complement of check-in and don't affect the counter.
  def handle_event(:child_marked_absent, %Event{} = event) do
    Logger.debug("ProviderSessionDetails ignoring child_marked_absent (no effect on checked_in_count)",
      record_id: event.entity_id
    )
  end

  # Bulk update scoped to :scheduled rows only — historical rows retain pre-existing attribution.
  def handle_event(:staff_assigned_to_program, %Event{payload: %{staff_member_id: staff_id, program_id: program_id}}) do
    staff_name = lookup_staff_name(staff_id)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(d in ProviderSessionDetailSchema,
      where: d.program_id == ^program_id and d.status == :scheduled
    )
    |> Repo.update_all(
      set: [
        current_assigned_staff_id: staff_id,
        current_assigned_staff_name: staff_name,
        updated_at: now
      ]
    )
  end

  # Historical rows retain pre-existing attribution as audit trail; only :scheduled rows are cleared.
  def handle_event(:staff_unassigned_from_program, %Event{payload: %{program_id: program_id}}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(d in ProviderSessionDetailSchema,
      where: d.program_id == ^program_id and d.status == :scheduled
    )
    |> Repo.update_all(
      set: [
        current_assigned_staff_id: nil,
        current_assigned_staff_name: nil,
        updated_at: now
      ]
    )
  end

  # Rebuilds from programs + program_sessions + staff assignments + participation counts.
  # Design notes:
  # * UUIDs cast to ::text so Postgrex returns strings (Ecto :binary_id accepts them on insert).
  # * Status arrives as text; String.to_existing_atom/1 converts (safe: fixed four enum values).
  # * Upsert preserves session_id, inserted_at, and cover_staff_* (not derivable from write tables).
  # * Raises on DB failure so WithBootstrapRetry can schedule a retry.
  defp bootstrap_session_details do
    # LATERAL subquery picks exactly one active staff assignment (earliest-assigned wins, matching
    # resolve_program_context/1). Without LIMIT 1 a program with N staff would produce N rows per
    # session and break the ON CONFLICT target.
    sql = """
    SELECT
      ps.id::text                            AS session_id,
      ps.program_id::text                    AS program_id,
      p.title                                AS program_title,
      p.provider_id::text                    AS provider_id,
      ps.session_date,
      ps.start_time,
      ps.end_time,
      ps.status::text                        AS status,
      staff.staff_member_id::text            AS current_assigned_staff_id,
      staff.first_name                       AS staff_first_name,
      staff.last_name                        AS staff_last_name,
      COALESCE(counts.checked_in, 0)         AS checked_in_count,
      COALESCE(counts.total, 0)              AS total_count
    FROM program_sessions ps
    JOIN programs p ON p.id = ps.program_id
    LEFT JOIN LATERAL (
      SELECT psa.staff_member_id, sm.first_name, sm.last_name
      FROM program_staff_assignments psa
      LEFT JOIN staff_members sm ON sm.id = psa.staff_member_id
      WHERE psa.program_id = ps.program_id
        AND psa.unassigned_at IS NULL
      ORDER BY psa.assigned_at ASC
      LIMIT 1
    ) staff ON TRUE
    LEFT JOIN (
      SELECT session_id,
             COUNT(*) FILTER (WHERE status IN ('checked_in','checked_out')) AS checked_in,
             COUNT(*) AS total
      FROM participation_records
      GROUP BY session_id
    ) counts ON counts.session_id = ps.id
    """

    case Repo.query(sql) do
      {:ok, %{rows: []}} ->
        0

      {:ok, %{rows: rows}} ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        attrs_list =
          Enum.map(rows, fn [
                              session_id,
                              program_id,
                              program_title,
                              provider_id,
                              session_date,
                              start_time,
                              end_time,
                              status,
                              staff_id,
                              staff_first,
                              staff_last,
                              checked_in_count,
                              total_count
                            ] ->
            %{
              session_id: session_id,
              program_id: program_id,
              program_title: program_title,
              provider_id: provider_id,
              session_date: session_date,
              start_time: start_time,
              end_time: end_time,
              status: String.to_existing_atom(status),
              current_assigned_staff_id: staff_id,
              current_assigned_staff_name: build_staff_name(staff_first, staff_last),
              checked_in_count: checked_in_count,
              total_count: total_count,
              inserted_at: now,
              updated_at: now
            }
          end)

        {count, _} =
          Repo.insert_all(
            ProviderSessionDetailSchema,
            attrs_list,
            on_conflict: {:replace_all_except, [:session_id, :inserted_at, :cover_staff_id, :cover_staff_name]},
            conflict_target: [:session_id]
          )

        count

      {:error, reason} ->
        raise "ProviderSessionDetails bootstrap failed: #{inspect(reason)}"
    end
  end

  defp project_session_created(%{session_id: session_id, program_id: program_id} = payload) do
    case resolve_program_context(program_id) do
      %{program_title: title, provider_id: provider_id} = ctx
      when not is_nil(title) and not is_nil(provider_id) ->
        do_insert_session(payload, ctx)

      _ ->
        Logger.warning(
          "ProviderSessionDetails session_created skipped: program not found",
          session_id: session_id,
          program_id: program_id
        )

        :ok
    end
  end

  defp do_insert_session(
         %{
           session_id: session_id,
           program_id: program_id,
           session_date: session_date,
           start_time: start_time,
           end_time: end_time
         },
         %{program_title: program_title, provider_id: provider_id, staff_id: staff_id, staff_name: staff_name}
       ) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs = %{
      session_id: session_id,
      program_id: program_id,
      program_title: program_title,
      provider_id: provider_id,
      session_date: session_date,
      start_time: start_time,
      end_time: end_time,
      status: :scheduled,
      current_assigned_staff_id: staff_id,
      current_assigned_staff_name: staff_name,
      checked_in_count: 0,
      total_count: 0,
      inserted_at: now,
      updated_at: now
    }

    Repo.insert_all(
      ProviderSessionDetailSchema,
      [attrs],
      on_conflict:
        {:replace_all_except,
         [
           :session_id,
           :inserted_at,
           :status,
           :checked_in_count,
           :total_count,
           :cover_staff_id,
           :cover_staff_name
         ]},
      conflict_target: [:session_id]
    )
  end

  defp update_status(session_id, status) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(d in ProviderSessionDetailSchema, where: d.session_id == ^session_id)
    |> Repo.update_all(set: [status: status, updated_at: now])
    |> warn_if_missing("status transition", session_id: session_id, target_status: status)
  end

  # Makes zero-row UPDATEs observable — events for unknown session_ids aren't silently dropped.
  defp warn_if_missing({0, _}, event_name, metadata) do
    Logger.warning(
      "ProviderSessionDetails #{event_name} skipped: session not found",
      metadata
    )
  end

  defp warn_if_missing(_result, _event_name, _metadata), do: :ok

  defp resolve_program_context(program_id) do
    sql = """
    SELECT p.title,
           p.provider_id,
           psa.staff_member_id,
           sm.first_name,
           sm.last_name
    FROM programs p
    LEFT JOIN program_staff_assignments psa
           ON psa.program_id = p.id
          AND psa.unassigned_at IS NULL
    LEFT JOIN staff_members sm ON sm.id = psa.staff_member_id
    WHERE p.id = $1
    ORDER BY psa.assigned_at ASC NULLS LAST
    LIMIT 1
    """

    case Repo.query(sql, [Ecto.UUID.dump!(program_id)]) do
      {:ok, %{rows: [[title, provider_id_bin, staff_id_bin, first_name, last_name]]}} ->
        %{
          program_title: title,
          provider_id: Ecto.UUID.cast!(provider_id_bin),
          staff_id: cast_uuid_or_nil(staff_id_bin),
          staff_name: build_staff_name(first_name, last_name)
        }

      _ ->
        %{program_title: nil, provider_id: nil, staff_id: nil, staff_name: nil}
    end
  end

  defp cast_uuid_or_nil(nil), do: nil
  defp cast_uuid_or_nil(bin), do: Ecto.UUID.cast!(bin)

  # Event payload carries only IDs; looks up name from staff_members (source of truth).
  defp lookup_staff_name(staff_id) do
    case Repo.query(
           "SELECT first_name, last_name FROM staff_members WHERE id = $1",
           [Ecto.UUID.dump!(staff_id)]
         ) do
      {:ok, %{rows: [[first_name, last_name]]}} -> build_staff_name(first_name, last_name)
      _ -> nil
    end
  end

  defp build_staff_name(nil, nil), do: nil
  defp build_staff_name(first, nil), do: first
  defp build_staff_name(nil, last), do: last
  defp build_staff_name(first, last), do: "#{first} #{last}"
end
