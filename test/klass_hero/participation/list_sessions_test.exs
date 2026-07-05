defmodule KlassHero.Participation.ListSessionsTest do
  @moduledoc """
  Integration tests for ListSessions use case.

  Tests listing sessions with different filter criteria.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Participation.ProgramSession

  describe "execute/1 with program_id filter" do
    test "returns sessions for a program ordered by date and time" do
      program = insert(:program_schema)

      insert(:program_session_schema,
        program_id: program.id,
        session_date: ~D[2025-02-17],
        start_time: ~T[09:00:00]
      )

      insert(:program_session_schema,
        program_id: program.id,
        session_date: ~D[2025-02-15],
        start_time: ~T[09:00:00]
      )

      insert(:program_session_schema,
        program_id: program.id,
        session_date: ~D[2025-02-16],
        start_time: ~T[14:00:00],
        end_time: ~T[17:00:00]
      )

      insert(:program_session_schema,
        program_id: program.id,
        session_date: ~D[2025-02-16],
        start_time: ~T[09:00:00]
      )

      sessions = KlassHero.Participation.list_sessions(%{program_id: program.id})
      assert length(sessions) == 4
      assert Enum.all?(sessions, &match?(%ProgramSession{}, &1))

      dates = Enum.map(sessions, & &1.session_date)
      assert dates == [~D[2025-02-15], ~D[2025-02-16], ~D[2025-02-16], ~D[2025-02-17]]

      same_day_sessions = Enum.filter(sessions, &(&1.session_date == ~D[2025-02-16]))
      times = Enum.map(same_day_sessions, & &1.start_time)
      assert times == [~T[09:00:00], ~T[14:00:00]]
    end

    test "returns empty list when program has no sessions" do
      program = insert(:program_schema)

      sessions = KlassHero.Participation.list_sessions(%{program_id: program.id})
      assert sessions == []
    end

    test "does not return sessions from other programs" do
      program1 = insert(:program_schema)
      program2 = insert(:program_schema)

      insert(:program_session_schema, program_id: program1.id)
      insert(:program_session_schema, program_id: program2.id)

      sessions = KlassHero.Participation.list_sessions(%{program_id: program1.id})
      assert length(sessions) == 1
      assert Enum.all?(sessions, &(&1.program_id == program1.id))
    end
  end

  describe "execute/1 with date filter" do
    test "returns sessions for a specific date ordered by time" do
      program = insert(:program_schema)
      target_date = ~D[2025-02-15]

      insert(:program_session_schema,
        program_id: program.id,
        session_date: target_date,
        start_time: ~T[14:00:00],
        end_time: ~T[17:00:00]
      )

      insert(:program_session_schema,
        program_id: program.id,
        session_date: target_date,
        start_time: ~T[09:00:00]
      )

      insert(:program_session_schema,
        program_id: program.id,
        session_date: ~D[2025-02-16],
        start_time: ~T[09:00:00]
      )

      sessions = KlassHero.Participation.list_sessions(%{date: target_date})
      assert length(sessions) == 2
      assert Enum.all?(sessions, &(&1.session_date == target_date))

      times = Enum.map(sessions, & &1.start_time)
      assert times == [~T[09:00:00], ~T[14:00:00]]
    end

    test "returns empty list when no sessions for date" do
      target_date = ~D[2025-02-15]

      sessions = KlassHero.Participation.list_sessions(%{date: target_date})
      assert sessions == []
    end
  end

  describe "execute/1 with empty map" do
    test "returns today's sessions by default" do
      # When no filter is specified, it defaults to today's date
      sessions = KlassHero.Participation.list_sessions(%{})
      assert is_list(sessions)
    end
  end

  describe "execute_admin/1" do
    setup do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id, title: "Test Program")

      insert(:program_session_schema,
        program_id: program.id,
        session_date: Date.utc_today(),
        status: "scheduled"
      )

      %{provider: provider, program: program}
    end

    test "defaults to today when no date filter provided" do
      results = KlassHero.Participation.list_admin_sessions(%{})
      assert length(results) == 1
      assert hd(results).program_name == "Test Program"
    end

    test "uses provided date filter instead of default" do
      yesterday = Date.add(Date.utc_today(), -1)
      results = KlassHero.Participation.list_admin_sessions(%{date: yesterday})
      assert results == []
    end

    test "passes through provider_id filter" do
      other_provider = insert(:provider_profile_schema)
      results = KlassHero.Participation.list_admin_sessions(%{provider_id: other_provider.id})
      assert results == []
    end
  end
end
