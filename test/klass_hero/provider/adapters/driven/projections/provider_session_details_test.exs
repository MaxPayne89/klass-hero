defmodule KlassHero.Provider.Adapters.Driven.Projections.ProviderSessionDetailsTest do
  use KlassHero.DataCase, async: false

  import Ecto.Query
  import ExUnit.CaptureLog
  import KlassHero.Factory

  alias KlassHero.Provider.Adapters.Driven.Projections.ProviderSessionDetails
  alias KlassHero.Provider.Domain.Events.ProviderEvents
  alias KlassHero.Provider.ProgramStaffAssignment
  alias KlassHero.Provider.SessionDetail
  alias KlassHero.Provider.StaffMember
  alias KlassHero.Repo
  alias KlassHero.Shared.Domain.Events.Event

  @test_server_name :test_provider_session_details

  setup do
    start_supervised!({ProviderSessionDetails, name: @test_server_name})
    # Drain bootstrap before running the test body.
    :sys.get_state(@test_server_name)
    :ok
  end

  test "starts and responds to a ping call" do
    assert Process.whereis(@test_server_name) |> is_pid()
  end

  describe "session_created" do
    test "inserts a row with defaults, resolving program_title and provider_id" do
      # programs FK on provider_id requires a real provider row.
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id, title: "Judo")
      session_id = Ecto.UUID.generate()

      broadcast(:session_created, session_id, %{
        session_id: session_id,
        program_id: program.id,
        session_date: ~D[2026-05-01],
        start_time: ~T[15:00:00],
        end_time: ~T[16:00:00]
      })

      row = Repo.get(SessionDetail, session_id)

      assert row != nil
      assert row.program_id == program.id
      assert row.program_title == "Judo"
      assert row.provider_id == provider.id
      assert row.session_date == ~D[2026-05-01]
      assert row.start_time == ~T[15:00:00]
      assert row.end_time == ~T[16:00:00]
      assert row.status == :scheduled
      assert row.checked_in_count == 0
      assert row.total_count == 0
      assert row.current_assigned_staff_id == nil
      assert row.current_assigned_staff_name == nil
    end

    test "resolves current_assigned_staff_id/name from active program_staff_assignments row" do
      # Exercise the happy-path active-staff resolution (WHERE unassigned_at IS NULL):
      # the row carries the seeded staff id + concatenated "First Last" name.
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

      session_id = Ecto.UUID.generate()

      broadcast(:session_created, session_id, %{
        session_id: session_id,
        program_id: program.id,
        session_date: ~D[2026-05-02],
        start_time: ~T[10:00:00],
        end_time: ~T[11:00:00]
      })

      row = Repo.get(SessionDetail, session_id)

      assert row != nil
      assert row.current_assigned_staff_id == staff.id
      assert row.current_assigned_staff_name == "Ada Lovelace"
    end

    test "duplicate delivery preserves evolved state written by other handlers" do
      # session_created must be a no-op on duplicate (at-least-once) delivery — it
      # must NOT stomp status/counts/cover_staff_* that other handlers evolved
      # between deliveries.
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id, title: "Aikido")
      session_id = Ecto.UUID.generate()

      payload = %{
        session_id: session_id,
        program_id: program.id,
        session_date: ~D[2026-05-03],
        start_time: ~T[09:00:00],
        end_time: ~T[10:00:00]
      }

      broadcast(:session_created, session_id, payload)

      # Simulate evolved state written by other handlers between deliveries.
      cover_staff_id = Ecto.UUID.generate()

      Repo.update_all(
        from(d in SessionDetail, where: d.session_id == ^session_id),
        set: [
          status: :in_progress,
          checked_in_count: 5,
          total_count: 10,
          cover_staff_id: cover_staff_id,
          cover_staff_name: "Cover Person"
        ]
      )

      # Replay the same event.
      broadcast(:session_created, session_id, payload)

      row = Repo.get(SessionDetail, session_id)

      assert row != nil
      assert row.status == :in_progress
      assert row.checked_in_count == 5
      assert row.total_count == 10
      assert row.cover_staff_id == cover_staff_id
      assert row.cover_staff_name == "Cover Person"
    end

    test "skips the insert and warns when the program does not exist" do
      # program_title and provider_id are NOT NULL, so a session_created whose
      # program_id is absent from the write table (reordering/replay/deletion)
      # must be skipped with a warning; bootstrap reconciles later.
      unknown_program_id = Ecto.UUID.generate()
      session_id = Ecto.UUID.generate()

      log =
        capture_log(fn ->
          broadcast(:session_created, session_id, %{
            session_id: session_id,
            program_id: unknown_program_id,
            session_date: ~D[2026-05-01],
            start_time: ~T[09:00:00],
            end_time: ~T[10:00:00]
          })
        end)

      assert Repo.get(SessionDetail, session_id) == nil
      assert log =~ "session_created skipped: program not found"
      assert log =~ session_id
      assert log =~ unknown_program_id
    end
  end

  describe "status transitions" do
    setup :insert_seed_session

    test "session_started sets status=:in_progress", %{session_id: session_id} do
      broadcast(:session_started, session_id, %{session_id: session_id, program_id: "prog"})

      assert %{status: :in_progress} = reload(session_id)
    end

    test "session_completed sets status=:completed", %{session_id: session_id} do
      broadcast(:session_completed, session_id, %{
        session_id: session_id,
        program_id: "prog",
        provider_id: "prv",
        program_title: "Judo"
      })

      assert %{status: :completed} = reload(session_id)
    end

    test "session_cancelled sets status=:cancelled", %{session_id: session_id} do
      broadcast(:session_cancelled, session_id, %{session_id: session_id, program_id: "prog"})

      assert %{status: :cancelled} = reload(session_id)
    end

    test "logs a warning when the session row is missing" do
      unknown_id = Ecto.UUID.generate()

      log =
        capture_log(fn ->
          broadcast(:session_started, unknown_id, %{session_id: unknown_id, program_id: "prog"})
        end)

      assert log =~ "status transition skipped"
      assert log =~ unknown_id
    end
  end

  describe "roster_seeded" do
    setup :insert_seed_session

    test "sets total_count from seeded_count", %{session_id: session_id} do
      broadcast(:roster_seeded, session_id, %{
        session_id: session_id,
        program_id: "prog",
        seeded_count: 7
      })

      assert %{total_count: 7} = reload(session_id)
    end

    test "accumulates across seedings instead of overwriting", %{session_id: session_id} do
      # seeded_count is the *delta* an insert added, not a running total: a later
      # back-fill of one child must not stomp an existing roster of five.
      broadcast(:roster_seeded, session_id, %{
        session_id: session_id,
        program_id: "prog",
        seeded_count: 5
      })

      broadcast(:roster_seeded, session_id, %{
        session_id: session_id,
        program_id: "prog",
        seeded_count: 1
      })

      assert %{total_count: 6} = reload(session_id)
    end

    test "logs a warning when the session row is missing" do
      unknown_id = Ecto.UUID.generate()

      log =
        capture_log(fn ->
          broadcast(:roster_seeded, unknown_id, %{
            session_id: unknown_id,
            program_id: "prog",
            seeded_count: 3
          })
        end)

      assert log =~ "roster_seeded skipped"
      assert log =~ unknown_id
    end
  end

  describe "attendance counters" do
    setup :insert_seed_session

    test "child_checked_in increments checked_in_count", %{session_id: session_id} do
      broadcast(:child_checked_in, "rec-1", %{
        record_id: "rec-1",
        session_id: session_id,
        child_id: "c-1"
      })

      assert %{checked_in_count: 1} = reload(session_id)
    end

    test "two check-ins increment to 2", %{session_id: session_id} do
      broadcast(:child_checked_in, "rec-1", %{
        record_id: "rec-1",
        session_id: session_id,
        child_id: "c-1"
      })

      broadcast(:child_checked_in, "rec-2", %{
        record_id: "rec-2",
        session_id: session_id,
        child_id: "c-2"
      })

      assert %{checked_in_count: 2} = reload(session_id)
    end

    test "child_checked_out does not decrement", %{session_id: session_id} do
      broadcast(:child_checked_in, "rec-1", %{
        record_id: "rec-1",
        session_id: session_id,
        child_id: "c-1"
      })

      assert %{checked_in_count: 1} = reload(session_id)

      broadcast(:child_checked_out, "rec-1", %{
        record_id: "rec-1",
        session_id: session_id,
        child_id: "c-1"
      })

      assert %{checked_in_count: 1} = reload(session_id)
    end

    test "child_marked_absent does not change count", %{session_id: session_id} do
      broadcast(:child_marked_absent, "rec-1", %{
        record_id: "rec-1",
        session_id: session_id,
        child_id: "c-1"
      })

      assert %{checked_in_count: 0} = reload(session_id)
    end

    test "logs a warning when child_checked_in arrives for an unknown session" do
      unknown_id = Ecto.UUID.generate()

      log =
        capture_log(fn ->
          broadcast(:child_checked_in, "rec-ghost", %{
            record_id: "rec-ghost",
            session_id: unknown_id,
            child_id: "c-1"
          })
        end)

      assert log =~ "child_checked_in skipped"
      assert log =~ unknown_id
    end
  end

  describe "staff assignment" do
    test "staff_assigned_to_program updates scheduled sessions for the program and skips non-scheduled ones" do
      # Cover staff on the bulk update path — only :scheduled rows flip to the new
      # staff; already-started/completed rows retain their state.
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)

      staff =
        insert(:staff_member_schema,
          provider_id: provider.id,
          first_name: "Alice",
          last_name: "Smith"
        )

      scheduled_session_id = Ecto.UUID.generate()
      completed_session_id = Ecto.UUID.generate()

      insert_program_session(
        session_id: scheduled_session_id,
        program_id: program.id,
        provider_id: provider.id,
        status: :scheduled
      )

      insert_program_session(
        session_id: completed_session_id,
        program_id: program.id,
        provider_id: provider.id,
        status: :completed
      )

      broadcast_provider(:staff_assigned_to_program, staff.id, %{
        staff_member_id: staff.id,
        program_id: program.id,
        provider_id: provider.id,
        staff_user_id: Ecto.UUID.generate()
      })

      scheduled = reload(scheduled_session_id)
      completed = reload(completed_session_id)

      assert scheduled.current_assigned_staff_id == staff.id
      assert scheduled.current_assigned_staff_name == "Alice Smith"
      assert completed.current_assigned_staff_id == nil
      assert completed.current_assigned_staff_name == nil
    end

    test "staff_unassigned_from_program clears staff fields on scheduled rows for the program" do
      # Once a session starts/ends, its historical staff attribution persists; only
      # upcoming (:scheduled) sessions lose the assignment.
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)

      staff =
        insert(:staff_member_schema,
          provider_id: provider.id,
          first_name: "Bob",
          last_name: "Jones"
        )

      scheduled_session_id = Ecto.UUID.generate()
      completed_session_id = Ecto.UUID.generate()

      insert_program_session(
        session_id: scheduled_session_id,
        program_id: program.id,
        provider_id: provider.id,
        status: :scheduled,
        current_assigned_staff_id: staff.id,
        current_assigned_staff_name: "Bob Jones"
      )

      insert_program_session(
        session_id: completed_session_id,
        program_id: program.id,
        provider_id: provider.id,
        status: :completed,
        current_assigned_staff_id: staff.id,
        current_assigned_staff_name: "Bob Jones"
      )

      broadcast_provider(:staff_unassigned_from_program, staff.id, %{
        staff_member_id: staff.id,
        program_id: program.id,
        provider_id: provider.id,
        staff_user_id: Ecto.UUID.generate()
      })

      scheduled = reload(scheduled_session_id)
      completed = reload(completed_session_id)

      assert scheduled.current_assigned_staff_id == nil
      assert scheduled.current_assigned_staff_name == nil
      assert completed.current_assigned_staff_id == staff.id
      assert completed.current_assigned_staff_name == "Bob Jones"
    end
  end

  describe "staff deactivation (#1237)" do
    # Built from the real ProviderEvents constructor rather than the local
    # Event.new/5 helpers: the suite runs on TestOutbox, so nothing else in this
    # file pairs a producer with its consumer, and a hand-rolled payload would
    # hide drift between the two.
    setup do
      provider = insert(:provider_profile_schema)

      staff =
        insert(:staff_member_schema,
          provider_id: provider.id,
          first_name: "Carol",
          last_name: "Dane"
        )

      %{provider: provider, staff: staff}
    end

    defp deactivate(staff) do
      staff
      |> ProviderEvents.staff_member_deactivated()
      |> ProviderSessionDetails.project()
    end

    defp session_assigned_to(provider, staff, status) do
      program = insert(:program_schema, provider_id: provider.id)
      session_id = Ecto.UUID.generate()

      insert_program_session(
        session_id: session_id,
        program_id: program.id,
        provider_id: provider.id,
        status: status,
        current_assigned_staff_id: staff.id,
        current_assigned_staff_name: StaffMember.full_name(staff)
      )

      session_id
    end

    test "clears the staff member from scheduled sessions across every program", ctx do
      # Deactivation is not per-program, so unlike :staff_unassigned_from_program
      # this clause must reach every program the staff member was assigned to.
      first = session_assigned_to(ctx.provider, ctx.staff, :scheduled)
      second = session_assigned_to(ctx.provider, ctx.staff, :scheduled)

      deactivate(ctx.staff)

      for session_id <- [first, second] do
        row = reload(session_id)
        assert is_nil(row.current_assigned_staff_id), "expected #{session_id} to be cleared"
        assert is_nil(row.current_assigned_staff_name), "expected #{session_id} to be cleared"
      end
    end

    test "leaves historical rows attributed", ctx do
      completed = session_assigned_to(ctx.provider, ctx.staff, :completed)

      deactivate(ctx.staff)

      row = reload(completed)
      assert row.current_assigned_staff_id == ctx.staff.id
      assert row.current_assigned_staff_name == "Carol Dane"
    end

    test "does not clear another staff member's sessions", ctx do
      other = insert(:staff_member_schema, provider_id: ctx.provider.id, first_name: "Dee", last_name: "Ell")
      mine = session_assigned_to(ctx.provider, ctx.staff, :scheduled)
      theirs = session_assigned_to(ctx.provider, other, :scheduled)

      deactivate(ctx.staff)

      assert is_nil(reload(mine).current_assigned_staff_id)
      assert reload(theirs).current_assigned_staff_id == other.id
    end
  end

  # Projects in the test process, exactly as the delivery job does — no broadcast,
  # no mailbox fence, the projection GenServer is not in this path.
  defp broadcast(event_type, entity_id, payload) do
    event = Event.new(event_type, :participation, :session, entity_id, payload)

    ProviderSessionDetails.project(event)
  end

  defp broadcast_provider(event_type, entity_id, payload) do
    event = Event.new(event_type, :provider, :staff, entity_id, payload)

    ProviderSessionDetails.project(event)
  end

  defp insert_program_session(attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    base = %{
      session_id: Ecto.UUID.generate(),
      program_id: Ecto.UUID.generate(),
      program_title: "P",
      provider_id: Ecto.UUID.generate(),
      session_date: ~D[2026-05-01],
      start_time: ~T[09:00:00],
      end_time: ~T[10:00:00],
      status: :scheduled,
      checked_in_count: 0,
      total_count: 0,
      inserted_at: now,
      updated_at: now
    }

    Repo.insert_all(SessionDetail, [Map.merge(base, Map.new(attrs))])
  end

  defp reload(session_id) do
    Repo.get(SessionDetail, session_id)
  end

  defp insert_seed_session(_ctx) do
    session_id = Ecto.UUID.generate()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert_all(SessionDetail, [
      %{
        session_id: session_id,
        program_id: Ecto.UUID.generate(),
        program_title: "X",
        provider_id: Ecto.UUID.generate(),
        session_date: ~D[2026-05-01],
        start_time: ~T[09:00:00],
        end_time: ~T[10:00:00],
        status: :scheduled,
        checked_in_count: 0,
        total_count: 0,
        inserted_at: now,
        updated_at: now
      }
    ])

    %{session_id: session_id}
  end

  describe "macro invariants after happy-path startup" do
    test "state.retry_count == 0 after first event projects successfully" do
      pid =
        start_supervised!(
          {ProviderSessionDetails, name: :"reg_#{System.unique_integer([:positive])}"},
          id: :regression_projection
        )

      :sys.get_state(pid)

      assert %{bootstrapped: true, retry_count: 0} = :sys.get_state(pid)

      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id, title: "Regression")
      session_id = Ecto.UUID.generate()

      event =
        Event.new(
          :session_created,
          :participation,
          :session,
          session_id,
          %{
            session_id: session_id,
            program_id: program.id,
            session_date: ~D[2026-05-01],
            start_time: ~T[09:00:00],
            end_time: ~T[10:00:00]
          }
        )

      assert :ok = ProviderSessionDetails.project(event)

      # Projecting is not a message to this process, so its bootstrap state is untouched.
      assert %{bootstrapped: true, retry_count: 0} = :sys.get_state(pid)
    end
  end
end
