defmodule KlassHero.Participation.Application.Queries.GetParticipationHistoryTest do
  @moduledoc """
  Integration tests for GetParticipationHistory use case.

  Tests participation history retrieval for children with optional date filtering.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Participation.ParticipationRecord

  describe "execute/1 with single child" do
    test "returns all participation records for a child" do
      child = insert(:child_schema)
      program = insert(:program_schema)

      session1 =
        insert(:program_session_schema,
          program_id: program.id,
          session_date: ~D[2025-02-15]
        )

      session2 =
        insert(:program_session_schema,
          program_id: program.id,
          session_date: ~D[2025-02-17]
        )

      insert(:participation_record_schema, session_id: session1.id, child_id: child.id)
      insert(:participation_record_schema, session_id: session2.id, child_id: child.id)

      assert {:ok, records} = KlassHero.Participation.get_participation_history(%{child_id: child.id})
      assert length(records) == 2
      assert Enum.all?(records, &match?(%ParticipationRecord{}, &1))
      assert Enum.all?(records, &(&1.child_id == child.id))
    end

    test "returns empty list when child has no records" do
      child = insert(:child_schema)

      assert {:ok, records} = KlassHero.Participation.get_participation_history(%{child_id: child.id})
      assert records == []
    end

    test "does not return records from other children" do
      child1 = insert(:child_schema)
      child2 = insert(:child_schema)
      session = insert(:program_session_schema)

      insert(:participation_record_schema, session_id: session.id, child_id: child1.id)
      insert(:participation_record_schema, session_id: session.id, child_id: child2.id)

      assert {:ok, records} = KlassHero.Participation.get_participation_history(%{child_id: child1.id})
      assert length(records) == 1
      assert hd(records).child_id == child1.id
    end

    test "filters by date range when provided" do
      child = insert(:child_schema)
      program = insert(:program_schema)

      session_in_range =
        insert(:program_session_schema,
          program_id: program.id,
          session_date: ~D[2025-02-15]
        )

      session_out_of_range =
        insert(:program_session_schema,
          program_id: program.id,
          session_date: ~D[2025-01-01]
        )

      insert(:participation_record_schema,
        session_id: session_in_range.id,
        child_id: child.id
      )

      insert(:participation_record_schema,
        session_id: session_out_of_range.id,
        child_id: child.id
      )

      assert {:ok, records} =
               KlassHero.Participation.get_participation_history(%{
                 child_id: child.id,
                 start_date: ~D[2025-02-01],
                 end_date: ~D[2025-02-28]
               })

      assert length(records) == 1
      assert hd(records).session_id == session_in_range.id
    end
  end

  describe "execute/1 with multiple children" do
    test "returns all participation records for multiple children" do
      child1 = insert(:child_schema)
      child2 = insert(:child_schema)
      session = insert(:program_session_schema)

      insert(:participation_record_schema, session_id: session.id, child_id: child1.id)
      insert(:participation_record_schema, session_id: session.id, child_id: child2.id)

      assert {:ok, records} =
               KlassHero.Participation.get_participation_history(%{child_ids: [child1.id, child2.id]})

      assert length(records) == 2
      child_ids = Enum.map(records, & &1.child_id)
      assert child1.id in child_ids
      assert child2.id in child_ids
    end

    test "returns empty list for empty child_ids list" do
      assert {:ok, records} = KlassHero.Participation.get_participation_history(%{child_ids: []})
      assert records == []
    end

    test "filters by date range when provided for multiple children" do
      child1 = insert(:child_schema)
      child2 = insert(:child_schema)
      program = insert(:program_schema)

      session_in_range =
        insert(:program_session_schema,
          program_id: program.id,
          session_date: ~D[2025-02-15]
        )

      session_out_of_range =
        insert(:program_session_schema,
          program_id: program.id,
          session_date: ~D[2025-01-01]
        )

      insert(:participation_record_schema,
        session_id: session_in_range.id,
        child_id: child1.id
      )

      insert(:participation_record_schema,
        session_id: session_out_of_range.id,
        child_id: child2.id
      )

      assert {:ok, records} =
               KlassHero.Participation.get_participation_history(%{
                 child_ids: [child1.id, child2.id],
                 start_date: ~D[2025-02-01],
                 end_date: ~D[2025-02-28]
               })

      assert length(records) == 1
      assert hd(records).child_id == child1.id
    end
  end
end
