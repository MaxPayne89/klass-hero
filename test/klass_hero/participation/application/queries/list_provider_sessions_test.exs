defmodule KlassHero.Participation.Application.Queries.ListProviderSessionsTest do
  @moduledoc """
  Integration tests for ListProviderSessions use case.

  Tests listing sessions for a provider on a specific date.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Participation.Application.Queries.ListProviderSessions
  alias KlassHero.Participation.ProgramSession

  describe "execute/1" do
    test "returns sessions for a date ordered by start time" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      target_date = ~D[2025-02-15]

      insert(:program_session_schema,
        program_id: program.id,
        session_date: target_date,
        start_time: ~T[16:00:00],
        end_time: ~T[19:00:00]
      )

      insert(:program_session_schema,
        program_id: program.id,
        session_date: target_date,
        start_time: ~T[10:00:00]
      )

      insert(:program_session_schema,
        program_id: program.id,
        session_date: ~D[2025-02-16],
        start_time: ~T[09:00:00]
      )

      assert {:ok, sessions} =
               ListProviderSessions.execute(%{provider_id: provider.id, date: target_date})

      assert length(sessions) == 2
      assert Enum.all?(sessions, &match?(%ProgramSession{}, &1))
      assert Enum.all?(sessions, &(&1.session_date == target_date))

      times = Enum.map(sessions, & &1.start_time)
      assert times == [~T[10:00:00], ~T[16:00:00]]
    end

    test "returns empty list when no sessions for date" do
      provider = insert(:provider_profile_schema)
      target_date = ~D[2025-02-15]

      assert {:ok, sessions} =
               ListProviderSessions.execute(%{provider_id: provider.id, date: target_date})

      assert sessions == []
    end

    test "returns sessions from multiple programs on same date" do
      provider = insert(:provider_profile_schema)
      program1 = insert(:program_schema, provider_id: provider.id)
      program2 = insert(:program_schema, provider_id: provider.id)
      target_date = ~D[2025-02-15]

      insert(:program_session_schema,
        program_id: program1.id,
        session_date: target_date,
        start_time: ~T[09:00:00]
      )

      insert(:program_session_schema,
        program_id: program2.id,
        session_date: target_date,
        start_time: ~T[14:00:00],
        end_time: ~T[17:00:00]
      )

      assert {:ok, sessions} =
               ListProviderSessions.execute(%{provider_id: provider.id, date: target_date})

      assert length(sessions) == 2
    end

    test "defaults to today when date not provided" do
      provider = insert(:provider_profile_schema)

      assert {:ok, sessions} = ListProviderSessions.execute(%{provider_id: provider.id})
      assert is_list(sessions)
    end
  end
end
