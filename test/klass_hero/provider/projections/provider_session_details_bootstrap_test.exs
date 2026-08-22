defmodule KlassHero.Provider.Projections.ProviderSessionDetailsBootstrapTest do
  use KlassHero.DataCase, async: false

  import Ecto.Query
  import KlassHero.Factory

  alias KlassHero.Provider.ProgramStaffAssignment
  alias KlassHero.Provider.Projections.ProviderSessionDetails
  alias KlassHero.Provider.SessionDetail
  alias KlassHero.Repo

  @tag :bootstrap
  test "bootstrap projects every existing session from write tables" do
    # Trigger: seed the write tables directly (no integration events emitted).
    # Why: exercises bootstrap's ability to self-heal the read table from the
    #      authoritative write tables — this is what rebuild/0 is for after
    #      seeds (which bypass the event bus).
    # Outcome: rebuild/0 projects every existing session row; the assertion
    #          verifies field resolution (program title, provider_id, status).
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id, title: "Judo")

    session_schema =
      insert(:program_session_schema,
        program_id: program.id,
        session_date: ~D[2026-05-01],
        start_time: ~T[15:00:00],
        end_time: ~T[16:00:00],
        status: "scheduled"
      )

    start_supervised!({ProviderSessionDetails, name: :bootstrap_test})
    :ok = ProviderSessionDetails.rebuild(:bootstrap_test)

    row = Repo.get(SessionDetail, session_schema.id)

    assert row != nil
    assert row.program_title == "Judo"
    assert row.provider_id == provider.id
    assert row.status == :scheduled
    assert row.session_date == ~D[2026-05-01]
    assert row.start_time == ~T[15:00:00]
    assert row.end_time == ~T[16:00:00]
    assert row.checked_in_count == 0
    assert row.total_count == 0
  end

  @tag :bootstrap
  test "bootstrap resolves current_assigned_staff_id/name from active assignment" do
    # Trigger: program has an active (unassigned_at IS NULL) staff assignment
    # Why: bootstrap must join program_staff_assignments + staff_members and
    #      concatenate first/last name the same way the event handlers do.
    # Outcome: row carries the staff id and "First Last" display name.
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id, title: "Karate")

    staff =
      insert(:staff_member_schema,
        provider_id: provider.id,
        first_name: "Ada",
        last_name: "Lovelace"
      )

    {:ok, _assignment} =
      %ProgramStaffAssignment{}
      |> ProgramStaffAssignment.create_changeset(%{
        provider_id: provider.id,
        staff_member_id: staff.id,
        program_id: program.id,
        assigned_at: DateTime.utc_now()
      })
      |> Repo.insert()

    session_schema =
      insert(:program_session_schema,
        program_id: program.id,
        session_date: ~D[2026-06-01],
        start_time: ~T[10:00:00],
        end_time: ~T[11:00:00],
        status: "scheduled"
      )

    start_supervised!({ProviderSessionDetails, name: :bootstrap_test_staff})
    :ok = ProviderSessionDetails.rebuild(:bootstrap_test_staff)

    row = Repo.get(SessionDetail, session_schema.id)

    assert row != nil
    assert row.current_assigned_staff_id == staff.id
    assert row.current_assigned_staff_name == "Ada Lovelace"
  end

  @tag :bootstrap
  test "bootstrap produces one row per session even when a program has multiple active staff" do
    # Trigger: a program has two active staff assignments (different staff_member_ids).
    #          The partial unique index program_staff_assignments_active_unique is
    #          (program_id, staff_member_id) WHERE unassigned_at IS NULL, so this
    #          is a legitimate state — not a data error.
    # Why: without the LATERAL LIMIT 1 subquery, the LEFT JOIN on
    #      program_staff_assignments would return N rows per session (one per
    #      active staff), and Repo.insert_all would trip Postgres's
    #      "ON CONFLICT DO UPDATE command cannot affect row a second time" error.
    # Outcome: bootstrap succeeds; exactly one row per session; the earliest-assigned
    #          staff wins (matching resolve_program_context/1's tie-breaker).
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id, title: "Yoga")

    first_staff =
      insert(:staff_member_schema, provider_id: provider.id, first_name: "Grace", last_name: "Hopper")

    second_staff =
      insert(:staff_member_schema, provider_id: provider.id, first_name: "Margaret", last_name: "Hamilton")

    first_assigned_at = ~U[2026-04-01 09:00:00Z]
    second_assigned_at = ~U[2026-04-02 09:00:00Z]

    {:ok, _} =
      %ProgramStaffAssignment{}
      |> ProgramStaffAssignment.create_changeset(%{
        provider_id: provider.id,
        staff_member_id: first_staff.id,
        program_id: program.id,
        assigned_at: first_assigned_at
      })
      |> Repo.insert()

    {:ok, _} =
      %ProgramStaffAssignment{}
      |> ProgramStaffAssignment.create_changeset(%{
        provider_id: provider.id,
        staff_member_id: second_staff.id,
        program_id: program.id,
        assigned_at: second_assigned_at
      })
      |> Repo.insert()

    session_schema =
      insert(:program_session_schema,
        program_id: program.id,
        session_date: ~D[2026-05-10],
        start_time: ~T[09:00:00],
        end_time: ~T[10:00:00],
        status: "scheduled"
      )

    start_supervised!({ProviderSessionDetails, name: :bootstrap_test_multi_staff})
    :ok = ProviderSessionDetails.rebuild(:bootstrap_test_multi_staff)

    # Only one row for the session (no duplicate-conflict crash)
    rows =
      Repo.all(
        from d in SessionDetail,
          where: d.session_id == ^session_schema.id
      )

    assert length(rows) == 1
    [row] = rows

    # Earliest-assigned staff wins (ORDER BY assigned_at ASC LIMIT 1)
    assert row.current_assigned_staff_id == first_staff.id
    assert row.current_assigned_staff_name == "Grace Hopper"
  end

  @tag :bootstrap
  test "bootstrap skips a deactivated staff member and picks the next active one" do
    # Trigger: the earliest-assigned staff member has been deactivated, a later
    #          one is still active. Both assignments remain live — deactivation
    #          ends the employment link, it does not unassign (#1237).
    # Why: the incremental path clears a deactivated staff member on
    #      :staff_member_deactivated, so a rebuild that re-named them would
    #      resurrect the stale attribution — and on the GDPR path that is an
    #      erased user's real name reappearing in a read table.
    # Outcome: the LATERAL picks the earliest *active* assignment.
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id, title: "Fencing")

    departed =
      insert(:staff_member_schema, provider_id: provider.id, first_name: "Gone", last_name: "Away", active: false)

    current =
      insert(:staff_member_schema, provider_id: provider.id, first_name: "Still", last_name: "Here")

    for {staff, assigned_at} <- [{departed, ~U[2026-04-01 09:00:00Z]}, {current, ~U[2026-04-02 09:00:00Z]}] do
      {:ok, _} =
        %ProgramStaffAssignment{}
        |> ProgramStaffAssignment.create_changeset(%{
          provider_id: provider.id,
          staff_member_id: staff.id,
          program_id: program.id,
          assigned_at: assigned_at
        })
        |> Repo.insert()
    end

    session_schema =
      insert(:program_session_schema,
        program_id: program.id,
        session_date: ~D[2026-05-11],
        start_time: ~T[09:00:00],
        end_time: ~T[10:00:00],
        status: "scheduled"
      )

    start_supervised!({ProviderSessionDetails, name: :bootstrap_test_inactive_staff})
    :ok = ProviderSessionDetails.rebuild(:bootstrap_test_inactive_staff)

    row = Repo.get(SessionDetail, session_schema.id)

    assert row.current_assigned_staff_id == current.id
    assert row.current_assigned_staff_name == "Still Here"
  end
end
