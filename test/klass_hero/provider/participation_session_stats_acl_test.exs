defmodule KlassHero.Provider.ParticipationSessionStatsACLTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Provider.ParticipationSessionStatsACL

  describe "list_completed_session_counts/0" do
    test "returns empty list when no completed sessions exist" do
      assert {:ok, []} = ParticipationSessionStatsACL.list_completed_session_counts()
    end

    test "counts completed sessions grouped by provider and program" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)

      insert(:program_session_schema,
        program_id: program.id,
        status: "completed",
        session_date: ~D[2026-01-01]
      )

      insert(:program_session_schema,
        program_id: program.id,
        status: "completed",
        session_date: ~D[2026-01-02]
      )

      # Non-completed session -- should NOT count
      insert(:program_session_schema,
        program_id: program.id,
        status: "scheduled",
        session_date: ~D[2026-01-03]
      )

      {:ok, results} = ParticipationSessionStatsACL.list_completed_session_counts()

      assert [result] = results
      assert result.provider_id == provider.id
      assert result.program_id == program.id
      assert result.program_title == program.title
      assert result.sessions_completed_count == 2
    end

    test "groups by program across multiple providers" do
      provider_a = insert(:provider_profile_schema)
      provider_b = insert(:provider_profile_schema)
      program_a = insert(:program_schema, provider_id: provider_a.id, title: "Art Class")
      program_b = insert(:program_schema, provider_id: provider_b.id, title: "Music Class")

      insert(:program_session_schema,
        program_id: program_a.id,
        status: "completed",
        session_date: ~D[2026-02-01]
      )

      insert(:program_session_schema,
        program_id: program_b.id,
        status: "completed",
        session_date: ~D[2026-02-01]
      )

      insert(:program_session_schema,
        program_id: program_b.id,
        status: "completed",
        session_date: ~D[2026-02-02]
      )

      {:ok, results} = ParticipationSessionStatsACL.list_completed_session_counts()

      by_provider = Map.new(results, &{&1.provider_id, &1})
      assert by_provider[provider_a.id].sessions_completed_count == 1
      assert by_provider[provider_b.id].sessions_completed_count == 2
    end
  end
end
