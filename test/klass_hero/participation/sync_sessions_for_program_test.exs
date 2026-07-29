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

  defp sessions_for(program_id) do
    from(s in ProgramSession, where: s.program_id == ^program_id, order_by: [asc: s.session_date])
    |> Repo.all()
  end

  describe "sync_sessions_for_program/1" do
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
      program = fortnightly_program()

      {:ok, manual} =
        Participation.create_session(%{
          program_id: program.id,
          session_date: Date.add(Date.utc_today(), 3),
          start_time: ~T[09:00:00],
          end_time: ~T[10:00:00]
        })

      assert {:ok, %{generated: 2, cancelled: 0}} = Participation.sync_sessions_for_program(program.id)

      reloaded = Repo.get!(ProgramSession, manual.id)
      assert reloaded.status == :scheduled
      assert reloaded.origin == :manual
    end

    test "leaves a completed session alone even when its slot leaves the schedule" do
      program = fortnightly_program()
      assert {:ok, %{generated: 2}} = Participation.sync_sessions_for_program(program.id)

      [first | _] = sessions_for(program.id)
      {:ok, _} = Participation.start_session(first.id)
      {:ok, _} = Participation.complete_session(first.id)

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
end
