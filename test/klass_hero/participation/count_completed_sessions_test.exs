defmodule KlassHero.Participation.CountCompletedSessionsTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Participation

  describe "count_completed_sessions/1" do
    test "returns zero for an empty program list, without querying" do
      assert Participation.count_completed_sessions([]) == 0
    end

    test "counts only sessions whose status is completed" do
      program = insert(:program_schema, provider_id: insert(:provider_profile_schema).id)

      for {status, date} <- [
            {"completed", ~D[2026-01-01]},
            {"completed", ~D[2026-01-02]},
            {"scheduled", ~D[2026-01-03]},
            {"cancelled", ~D[2026-01-04]},
            {"in_progress", ~D[2026-01-05]}
          ] do
        insert(:program_session_schema, program_id: program.id, status: status, session_date: date)
      end

      assert Participation.count_completed_sessions([program.id]) == 2
    end

    test "sums across the programs given and ignores the rest" do
      provider = insert(:provider_profile_schema)
      art = insert(:program_schema, provider_id: provider.id)
      music = insert(:program_schema, provider_id: provider.id)
      unasked = insert(:program_schema, provider_id: provider.id)

      for {program, date} <- [
            {art, ~D[2026-02-01]},
            {music, ~D[2026-02-01]},
            {music, ~D[2026-02-02]},
            {unasked, ~D[2026-02-03]}
          ] do
        insert(:program_session_schema,
          program_id: program.id,
          status: "completed",
          session_date: date
        )
      end

      assert Participation.count_completed_sessions([art.id, music.id]) == 3
    end

    test "an unknown program id contributes nothing rather than raising" do
      assert Participation.count_completed_sessions([Ecto.UUID.generate()]) == 0
    end
  end
end
