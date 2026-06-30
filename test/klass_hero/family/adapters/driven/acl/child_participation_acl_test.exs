defmodule KlassHero.Family.Adapters.Driven.ACL.ChildParticipationACLTest do
  use KlassHero.DataCase, async: true

  import Ecto.Query
  import KlassHero.Factory

  alias KlassHero.Family.Adapters.Driven.ACL.ChildParticipationACL
  alias KlassHero.Participation.BehavioralNote
  alias KlassHero.Participation.ParticipationRecord
  alias KlassHero.Repo

  describe "delete_all_for_child/1" do
    test "deletes participation records for a child" do
      record = insert(:participation_record_schema)

      assert {:ok, %{participation_records: 1, behavioral_notes: 0}} =
               ChildParticipationACL.delete_all_for_child(record.child_id)

      assert [] =
               Repo.all(from(r in ParticipationRecord, where: r.child_id == ^record.child_id))
    end

    test "deletes behavioral notes for a child before participation records" do
      record = insert(:participation_record_schema)

      insert(:behavioral_note_schema,
        participation_record_id: record.id,
        child_id: record.child_id,
        parent_id: record.parent_id
      )

      assert {:ok, %{participation_records: 1, behavioral_notes: 1}} =
               ChildParticipationACL.delete_all_for_child(record.child_id)

      assert [] =
               Repo.all(from(n in BehavioralNote, where: n.child_id == ^record.child_id))

      assert [] =
               Repo.all(from(r in ParticipationRecord, where: r.child_id == ^record.child_id))
    end

    test "returns zero count when no records exist" do
      {child, _parent} = insert_child_with_guardian()

      assert {:ok, %{participation_records: 0, behavioral_notes: 0}} =
               ChildParticipationACL.delete_all_for_child(child.id)
    end

    test "does not delete records for other children" do
      record1 = insert(:participation_record_schema)
      record2 = insert(:participation_record_schema)

      assert {:ok, %{participation_records: 1, behavioral_notes: 0}} =
               ChildParticipationACL.delete_all_for_child(record1.child_id)

      # Other child's record should still exist
      assert %ParticipationRecord{} = Repo.get!(ParticipationRecord, record2.id)
    end
  end
end
