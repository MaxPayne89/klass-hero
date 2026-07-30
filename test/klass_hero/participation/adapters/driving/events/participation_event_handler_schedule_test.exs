defmodule KlassHero.Participation.Adapters.Driving.Events.ParticipationEventHandlerScheduleTest do
  @moduledoc """
  The seam that makes schedule-derived sessions actually happen: a program write
  in another context reaching Participation's reconcile.
  """

  use KlassHero.DataCase, async: true

  import Ecto.Query
  import KlassHero.Factory

  alias KlassHero.Participation.Adapters.Driving.Events.ParticipationEventHandler
  alias KlassHero.Participation.ProgramSession
  alias KlassHero.Repo
  alias KlassHero.Shared.Domain.Events.Event

  @weekdays ~w(Monday Tuesday Wednesday Thursday Friday Saturday Sunday)

  defp scheduled_program(overrides \\ []) do
    today = Date.utc_today()

    insert(
      :program_schema,
      Keyword.merge(
        [
          meeting_days: [Enum.at(@weekdays, Date.day_of_week(today) - 1)],
          meeting_start_time: ~T[15:00:00],
          meeting_end_time: ~T[17:00:00],
          start_date: today,
          end_date: Date.add(today, 13)
        ],
        overrides
      )
    )
  end

  defp program_event(type, program_id) do
    Event.new(type, :program_catalog, :program, program_id, %{program_id: program_id})
  end

  defp session_count(program_id) do
    Repo.aggregate(from(s in ProgramSession, where: s.program_id == ^program_id), :count)
  end

  describe "program schedule events" do
    for event_type <- [:program_created, :program_updated] do
      test "#{event_type} generates the program's sessions" do
        program = scheduled_program()

        assert :ok = ParticipationEventHandler.handle_event(program_event(unquote(event_type), program.id))

        assert session_count(program.id) == 2
      end
    end

    test "a program without a full schedule is accepted, not an error" do
      program = scheduled_program(meeting_days: [])

      assert :ok = ParticipationEventHandler.handle_event(program_event(:program_updated, program.id))

      assert session_count(program.id) == 0
    end

    test "re-running on an unchanged schedule adds nothing" do
      program = scheduled_program()
      event = program_event(:program_updated, program.id)

      assert :ok = ParticipationEventHandler.handle_event(event)
      assert :ok = ParticipationEventHandler.handle_event(event)

      assert session_count(program.id) == 2
    end
  end

  describe "enrollment_created" do
    test "puts the enrolled child on the program's upcoming rosters" do
      program = scheduled_program()
      {child, _parent} = insert_child_with_guardian()

      assert :ok = ParticipationEventHandler.handle_event(program_event(:program_updated, program.id))

      insert(:enrollment_schema, program_id: program.id, child_id: child.id, status: :confirmed)

      event =
        Event.new(:enrollment_created, :enrollment, :enrollment, Ecto.UUID.generate(), %{
          child_id: child.id,
          program_id: program.id
        })

      assert :ok = ParticipationEventHandler.handle_event(event)

      session_ids = Repo.all(from(s in ProgramSession, where: s.program_id == ^program.id, select: s.id))

      for session_id <- session_ids do
        assert {:ok, %{roster: [entry]}} = KlassHero.Participation.get_session_with_roster(session_id)
        assert entry.record.child_id == child.id
      end
    end
  end
end
