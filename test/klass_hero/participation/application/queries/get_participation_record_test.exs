defmodule KlassHero.Participation.Application.Queries.GetParticipationRecordTest do
  @moduledoc """
  Integration tests for GetParticipationRecord use case.

  Tests retrieval of participation records by ID.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Participation.ParticipationRecord

  describe "execute/1" do
    test "returns participation record when found" do
      record_schema = insert(:participation_record_schema)

      assert {:ok, record} = KlassHero.Participation.get_participation_record(record_schema.id)
      assert %ParticipationRecord{} = record
      assert record.id == record_schema.id
    end

    test "returns error when record not found" do
      non_existent_id = Ecto.UUID.generate()

      assert {:error, :not_found} = KlassHero.Participation.get_participation_record(non_existent_id)
    end

    test "includes all record details" do
      session = insert(:program_session_schema)
      child = insert(:child_schema)
      staff_id = KlassHero.AccountsFixtures.unconfirmed_user_fixture().id
      check_in_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      check_out_time = DateTime.utc_now()

      record_schema =
        insert(:participation_record_schema,
          session_id: session.id,
          child_id: child.id,
          status: :checked_out,
          check_in_at: check_in_time,
          check_in_by: staff_id,
          check_in_notes: "Arrived on time",
          check_out_at: check_out_time,
          check_out_by: staff_id,
          check_out_notes: "Picked up by parent"
        )

      assert {:ok, record} = KlassHero.Participation.get_participation_record(record_schema.id)
      assert record.session_id == session.id
      assert record.child_id == child.id
      assert record.status == :checked_out
      assert record.check_in_notes == "Arrived on time"
      assert record.check_out_notes == "Picked up by parent"
    end
  end
end
