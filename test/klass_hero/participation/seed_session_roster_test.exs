defmodule KlassHero.Participation.SeedSessionRosterTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  describe "execute/2" do
    test "creates participation records for enrolled children" do
      enrollment = insert(:enrollment_schema, status: "confirmed")

      session =
        insert(:program_session_schema,
          program_id: enrollment.program_id,
          status: "scheduled"
        )

      assert :ok = KlassHero.Participation.seed_session_roster(session.id, enrollment.program_id)

      {:ok, %{roster: roster}} = KlassHero.Participation.get_session_with_roster(session.id)
      records = Enum.map(roster, & &1.record)
      assert length(records) == 1
      assert hd(records).child_id == enrollment.child_id
      assert hd(records).status == :registered
    end

    test "is idempotent — running twice does not duplicate records" do
      enrollment = insert(:enrollment_schema, status: "confirmed")

      session =
        insert(:program_session_schema,
          program_id: enrollment.program_id,
          status: "scheduled"
        )

      assert :ok = KlassHero.Participation.seed_session_roster(session.id, enrollment.program_id)
      assert :ok = KlassHero.Participation.seed_session_roster(session.id, enrollment.program_id)

      {:ok, %{roster: roster}} = KlassHero.Participation.get_session_with_roster(session.id)
      records = Enum.map(roster, & &1.record)
      assert length(records) == 1
    end

    test "handles program with no enrollments gracefully" do
      session = insert(:program_session_schema, status: "scheduled")

      assert :ok = KlassHero.Participation.seed_session_roster(session.id, session.program_id)

      {:ok, %{roster: roster}} = KlassHero.Participation.get_session_with_roster(session.id)
      records = Enum.map(roster, & &1.record)
      assert records == []
    end

    test "returns :ok when seeding fails (best-effort)" do
      enrollment = insert(:enrollment_schema, status: "confirmed")
      non_existent_session_id = Ecto.UUID.generate()

      assert :ok = KlassHero.Participation.seed_session_roster(non_existent_session_id, enrollment.program_id)
    end
  end
end
