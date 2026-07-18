defmodule KlassHero.Participation.ListUpcomingSessionsForProgramsTest do
  # async: false — the query-count assertion uses a process-global telemetry handler.
  use KlassHero.DataCase, async: false

  import KlassHero.Factory

  alias KlassHero.Participation
  alias KlassHero.QueryCounter

  describe "list_upcoming_sessions_for_programs/2" do
    setup do
      %{program_a: insert(:program_schema), program_b: insert(:program_schema), today: Date.utc_today()}
    end

    test "returns only sessions on or after from_date, across all given programs", %{
      program_a: a,
      program_b: b,
      today: today
    } do
      past = insert(:program_session_schema, program_id: a.id, session_date: Date.add(today, -3))
      today_session = insert(:program_session_schema, program_id: a.id, session_date: today)
      future = insert(:program_session_schema, program_id: b.id, session_date: Date.add(today, 5))

      ids =
        [a.id, b.id]
        |> Participation.list_upcoming_sessions_for_programs(today)
        |> Enum.map(& &1.id)

      assert today_session.id in ids
      assert future.id in ids
      refute past.id in ids
    end

    test "orders by session_date then start_time ascending", %{program_a: a, today: today} do
      later =
        insert(:program_session_schema, program_id: a.id, session_date: Date.add(today, 2), start_time: ~T[09:00:00])

      sooner =
        insert(:program_session_schema,
          program_id: a.id,
          session_date: Date.add(today, 1),
          start_time: ~T[15:00:00],
          end_time: ~T[16:00:00]
        )

      same_day_early =
        insert(:program_session_schema, program_id: a.id, session_date: Date.add(today, 1), start_time: ~T[08:00:00])

      ids =
        [a.id]
        |> Participation.list_upcoming_sessions_for_programs(today)
        |> Enum.map(& &1.id)

      assert ids == [same_day_early.id, sooner.id, later.id]
    end

    test "excludes sessions from programs not in the list", %{program_a: a, program_b: b, today: today} do
      insert(:program_session_schema, program_id: b.id, session_date: Date.add(today, 1))

      assert Participation.list_upcoming_sessions_for_programs([a.id], today) == []
    end

    test "issues a single query regardless of program count", %{today: today} do
      ids = for _ <- 1..3, do: insert(:program_schema).id

      queries = QueryCounter.count_only(fn -> Participation.list_upcoming_sessions_for_programs(ids, today) end)

      assert queries == 1
    end

    test "returns an empty list for an empty program list", %{today: today} do
      assert Participation.list_upcoming_sessions_for_programs([], today) == []
    end
  end
end
