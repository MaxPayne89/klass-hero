defmodule KlassHero.Participation.OutboxStagingTest do
  @moduledoc """
  What each Participation write path hands to durable delivery.

  These assert the *staging*, not the consumers: staging happens inside the write's
  transaction, so an event that is not staged is one that no amount of retrying can
  recover. The old suite could not express this — publication happened after the
  commit, from a bus handler, and no test connected a write to the event it owed.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Participation
  alias KlassHero.Shared.Adapters.Driven.Events.TestOutbox

  setup do
    TestOutbox.setup()

    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)

    {:ok, program: program}
  end

  defp staged_types, do: Enum.map(TestOutbox.staged(), & &1.event_type)

  defp create_session(program) do
    {:ok, session} =
      Participation.create_session(%{
        program_id: program.id,
        session_date: Date.utc_today(),
        start_time: ~T[09:00:00],
        end_time: ~T[10:00:00]
      })

    session
  end

  test "create_session stages session_created", %{program: program} do
    session = create_session(program)

    assert [:session_created] = staged_types()
    assert [%{entity_id: entity_id}] = TestOutbox.staged()
    assert entity_id == session.id
  end

  test "start_session stages session_started", %{program: program} do
    session = create_session(program)
    TestOutbox.setup()

    {:ok, _started} = Participation.start_session(session.id)

    assert [:session_started] = staged_types()
  end

  test "complete_session stages session_completed", %{program: program} do
    session = create_session(program)
    {:ok, _started} = Participation.start_session(session.id)
    TestOutbox.setup()

    {:ok, _completed} = Participation.complete_session(session.id)

    assert :session_completed in staged_types()
  end

  test "seed_session_roster stages roster_seeded", %{program: program} do
    session = create_session(program)
    TestOutbox.setup()

    :ok = Participation.seed_session_roster(session.id, program.id)

    assert [:roster_seeded] = staged_types()
  end

  # The one path that emits several events from a single transaction — they ride one
  # job, in this order.
  test "sync_sessions_for_program stages its whole transaction's events" do
    today = Date.utc_today()
    weekday = Enum.at(~w(Monday Tuesday Wednesday Thursday Friday Saturday Sunday), Date.day_of_week(today) - 1)

    program =
      insert(:program_schema,
        meeting_days: [weekday],
        meeting_start_time: ~T[15:00:00],
        meeting_end_time: ~T[17:00:00],
        start_date: today,
        end_date: Date.add(today, 13)
      )

    TestOutbox.setup()

    assert {:ok, %{generated: 2}} = Participation.sync_sessions_for_program(program.id)

    assert [:sessions_generated] = staged_types()
  end

  # Session notes have no cross-context consumer, so they were never promoted and
  # must stay unstaged — otherwise the outbox grows work with nowhere to deliver it.
  test "submitting a session note stages nothing", %{program: program} do
    session = create_session(program)
    child = insert(:child_schema)
    record = insert(:participation_record_schema, session_id: session.id, child_id: child.id, status: :checked_in)
    TestOutbox.setup()

    {:ok, _note} =
      Participation.submit_session_note(%{
        participation_record_id: record.id,
        provider_id: program.provider_id,
        content: "Had a great time"
      })

    assert [] = TestOutbox.staged()
  end
end
