defmodule KlassHero.Participation.SyncSessionsForProgramTest do
  @moduledoc """
  Reconciling a program's generated sessions against its recurring schedule.

  The operation is idempotent by design: `program_updated` carries a full
  snapshot rather than a diff, so the handler cannot tell a schedule edit from a
  title edit and must be safe to run on every write.
  """

  use KlassHero.DataCase, async: true

  import Ecto.Query
  import KlassHero.Factory

  alias KlassHero.Accounts.Scope
  alias KlassHero.Participation
  alias KlassHero.Participation.ProgramSession
  alias KlassHero.Repo

  @weekdays ~w(Monday Tuesday Wednesday Thursday Friday Saturday Sunday)

  defp weekday_name(date), do: Enum.at(@weekdays, Date.day_of_week(date) - 1)

  # A fortnight starting today, meeting on today's weekday: two occurrences,
  # today and a week from today.
  defp fortnightly_program(overrides \\ []) do
    today = Date.utc_today()

    insert(
      :program_schema,
      Keyword.merge(
        [
          meeting_days: [weekday_name(today)],
          meeting_start_time: ~T[15:00:00],
          meeting_end_time: ~T[17:00:00],
          start_date: today,
          end_date: Date.add(today, 13)
        ],
        overrides
      )
    )
  end

  # Written straight to the row: the facade path is covered in
  # update_program_integration_test.exs, and this file is about what sync reads.
  defp set_default_capacity(program, capacity) do
    from(p in "programs", where: p.id == type(^program.id, :binary_id))
    |> Repo.update_all(set: [default_session_capacity: capacity])
  end

  defp sessions_for(program_id) do
    from(s in ProgramSession, where: s.program_id == ^program_id, order_by: [asc: s.session_date])
    |> Repo.all()
  end

  describe "sync_sessions_for_program/1" do
    test "a generated session inherits the program's default Session Capacity" do
      program = fortnightly_program(default_session_capacity: 12)

      assert {:ok, %{generated: 2}} = Participation.sync_sessions_for_program(program.id)

      assert [first, second] = sessions_for(program.id)
      assert first.max_capacity == 12
      assert second.max_capacity == 12
    end

    test "changing the default realigns sessions already generated" do
      # The reason capacity is realigned rather than only seeded: the insert uses
      # `on_conflict: :nothing`, so a value copied at creation would be frozen and
      # a provider raising their capacity would see nothing change.
      program = fortnightly_program(default_session_capacity: 12)
      assert {:ok, %{generated: 2}} = Participation.sync_sessions_for_program(program.id)

      set_default_capacity(program, 8)

      assert {:ok, _} = Participation.sync_sessions_for_program(program.id)

      assert Enum.all?(sessions_for(program.id), &(&1.max_capacity == 8))
    end

    test "a capacity set by hand on a generated session survives a later sync" do
      # A provider can tune one date through the session edit form
      # (`ParticipationLive` -> `update_session/3`), and that number must outlive
      # every later program write. Realignment fills in what a Program dictates;
      # it does not overrule what a human decided about one date.
      provider = insert(:provider_profile_schema)

      program =
        fortnightly_program(default_session_capacity: 12, provider_id: provider.id)

      assert {:ok, %{generated: 2}} = Participation.sync_sessions_for_program(program.id)

      [generated | _] = sessions_for(program.id)

      {:ok, edited} =
        Participation.update_session(%Scope{provider: provider}, generated.id, %{max_capacity: 4})

      assert edited.origin == :generated

      set_default_capacity(program, 15)
      assert {:ok, _} = Participation.sync_sessions_for_program(program.id)

      assert Repo.get!(ProgramSession, generated.id).max_capacity == 4

      # ...while its untouched sibling still tracks the Program.
      others = Enum.reject(sessions_for(program.id), &(&1.id == generated.id))
      assert Enum.all?(others, &(&1.max_capacity == 15))
    end

    test "clearing the default returns generated sessions to uncapped" do
      program = fortnightly_program(default_session_capacity: 12)
      assert {:ok, %{generated: 2}} = Participation.sync_sessions_for_program(program.id)

      set_default_capacity(program, nil)

      assert {:ok, _} = Participation.sync_sessions_for_program(program.id)

      assert Enum.all?(sessions_for(program.id), &is_nil(&1.max_capacity))
    end

    test "a program naming no default generates uncapped sessions" do
      program = fortnightly_program(default_session_capacity: nil)

      assert {:ok, %{generated: 2}} = Participation.sync_sessions_for_program(program.id)

      assert Enum.all?(sessions_for(program.id), &is_nil(&1.max_capacity))
    end

    test "generates one session per scheduled date" do
      program = fortnightly_program()

      assert {:ok, %{generated: 2, cancelled: 0}} = Participation.sync_sessions_for_program(program.id)

      assert [first, second] = sessions_for(program.id)
      assert first.session_date == Date.utc_today()
      assert second.session_date == Date.add(Date.utc_today(), 7)
      assert first.start_time == ~T[15:00:00]
      assert first.end_time == ~T[17:00:00]
      assert first.status == :scheduled
      assert first.origin == :generated
    end

    test "is idempotent — a second run generates nothing" do
      program = fortnightly_program()

      assert {:ok, %{generated: 2}} = Participation.sync_sessions_for_program(program.id)
      assert {:ok, %{generated: 0, cancelled: 0}} = Participation.sync_sessions_for_program(program.id)

      assert length(sessions_for(program.id)) == 2
    end

    test "cancels generated sessions that fall out of the schedule" do
      program = fortnightly_program()
      assert {:ok, %{generated: 2}} = Participation.sync_sessions_for_program(program.id)

      # Move the meeting day to the following weekday: both old dates orphan.
      tomorrow = Date.add(Date.utc_today(), 1)
      {:ok, program} = update_meeting_days(program, [weekday_name(tomorrow)])

      assert {:ok, %{generated: 2, cancelled: 2}} = Participation.sync_sessions_for_program(program.id)

      statuses = sessions_for(program.id) |> Enum.frequencies_by(& &1.status)
      assert statuses == %{cancelled: 2, scheduled: 2}
    end

    test "revives a cancelled slot when the schedule swings back" do
      program = fortnightly_program()
      original_days = program.meeting_days

      assert {:ok, %{generated: 2}} = Participation.sync_sessions_for_program(program.id)

      tomorrow = Date.add(Date.utc_today(), 1)
      {:ok, program} = update_meeting_days(program, [weekday_name(tomorrow)])
      assert {:ok, %{cancelled: 2}} = Participation.sync_sessions_for_program(program.id)

      {:ok, program} = update_meeting_days(program, original_days)
      assert {:ok, %{generated: 0, cancelled: 2}} = Participation.sync_sessions_for_program(program.id)

      revived =
        sessions_for(program.id)
        |> Enum.filter(&(&1.session_date in [Date.utc_today(), Date.add(Date.utc_today(), 7)]))

      assert Enum.all?(revived, &(&1.status == :scheduled)),
             "a slot that returns to the schedule must come back, not stay cancelled"
    end

    test "never touches a manually created session" do
      # The program's default differs from the manual session's own capacity, so a
      # realignment that ignored `origin` would overwrite a number the provider typed.
      #
      # Deliberately dated on one of the schedule's own meeting days, at a different
      # time of day: on any other date the date filter alone would spare it, and the
      # test would pass with the `origin` scoping deleted.
      program = fortnightly_program(default_session_capacity: 12)

      {:ok, manual} =
        Participation.create_session(admin_scope(), %{
          program_id: program.id,
          session_date: Date.utc_today(),
          start_time: ~T[09:00:00],
          end_time: ~T[10:00:00],
          max_capacity: 4
        })

      assert {:ok, %{generated: 2, cancelled: 0}} = Participation.sync_sessions_for_program(program.id)

      reloaded = Repo.get!(ProgramSession, manual.id)
      assert reloaded.status == :scheduled
      assert reloaded.origin == :manual
      assert reloaded.max_capacity == 4
    end

    test "leaves a completed session alone even when its slot leaves the schedule" do
      program = fortnightly_program()
      assert {:ok, %{generated: 2}} = Participation.sync_sessions_for_program(program.id)

      [first | _] = sessions_for(program.id)
      {:ok, _} = Participation.start_session(admin_scope(), first.id)
      {:ok, _} = Participation.complete_session(admin_scope(), first.id)

      tomorrow = Date.add(Date.utc_today(), 1)
      {:ok, program} = update_meeting_days(program, [weekday_name(tomorrow)])

      assert {:ok, %{cancelled: 1}} = Participation.sync_sessions_for_program(program.id)
      assert Repo.get!(ProgramSession, first.id).status == :completed
    end

    test "refuses an incomplete schedule without writing anything" do
      program = fortnightly_program(meeting_days: [])

      assert {:error, :incomplete_schedule} = Participation.sync_sessions_for_program(program.id)
      assert sessions_for(program.id) == []
    end

    test "reports a missing program" do
      assert {:error, :program_not_found} = Participation.sync_sessions_for_program(Ecto.UUID.generate())
    end
  end

  defp update_meeting_days(program, days) do
    program
    |> Ecto.Changeset.change(%{meeting_days: days})
    |> Repo.update()
  end

  # An admin is authorized everywhere, so the scope stays out of a test whose
  # subject is not authorization.
  defp admin_scope, do: KlassHero.AccountsFixtures.admin_scope_fixture()
end
