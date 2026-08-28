defmodule KlassHero.Provider.ParticipationSessionStatsACLTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Provider.ParticipationSessionStatsACL

  describe "total_completed_sessions/1" do
    test "returns zero when the provider has no completed sessions" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)

      insert(:program_session_schema,
        program_id: program.id,
        status: "scheduled",
        session_date: ~D[2026-01-03]
      )

      assert ParticipationSessionStatsACL.total_completed_sessions(provider.id) == 0
    end

    test "counts only sessions whose status is completed" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)

      for {status, date} <- [
            {"completed", ~D[2026-01-01]},
            {"completed", ~D[2026-01-02]},
            {"scheduled", ~D[2026-01-03]},
            {"cancelled", ~D[2026-01-04]},
            {"in_progress", ~D[2026-01-05]}
          ] do
        insert(:program_session_schema, program_id: program.id, status: status, session_date: date)
      end

      assert ParticipationSessionStatsACL.total_completed_sessions(provider.id) == 2
    end

    test "sums across every program the provider owns" do
      provider = insert(:provider_profile_schema)
      art = insert(:program_schema, provider_id: provider.id, title: "Art Class")
      music = insert(:program_schema, provider_id: provider.id, title: "Music Class")

      for {program, date} <- [
            {art, ~D[2026-02-01]},
            {music, ~D[2026-02-01]},
            {music, ~D[2026-02-02]}
          ] do
        insert(:program_session_schema,
          program_id: program.id,
          status: "completed",
          session_date: date
        )
      end

      assert ParticipationSessionStatsACL.total_completed_sessions(provider.id) == 3
    end

    test "another provider's completed sessions are not counted" do
      provider = insert(:provider_profile_schema)
      other = insert(:provider_profile_schema)
      mine = insert(:program_schema, provider_id: provider.id)
      theirs = insert(:program_schema, provider_id: other.id)

      insert(:program_session_schema,
        program_id: mine.id,
        status: "completed",
        session_date: ~D[2026-03-01]
      )

      for date <- [~D[2026-03-01], ~D[2026-03-02]] do
        insert(:program_session_schema,
          program_id: theirs.id,
          status: "completed",
          session_date: date
        )
      end

      assert ParticipationSessionStatsACL.total_completed_sessions(provider.id) == 1
      assert ParticipationSessionStatsACL.total_completed_sessions(other.id) == 2
    end

    test "returns zero for a provider that owns no programs" do
      provider = insert(:provider_profile_schema)

      assert ParticipationSessionStatsACL.total_completed_sessions(provider.id) == 0
    end
  end
end
