defmodule KlassHero.Family.DeleteChildTest do
  @moduledoc """
  Cross-context cascade behaviour for `Family.delete_child/1`: consents,
  enrollments, participation records, and behavioral notes.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Enrollment.Adapters.Driven.Persistence.Schemas.EnrollmentSchema
  alias KlassHero.Family
  alias KlassHero.Family.Adapters.Driven.Persistence.Schemas.ConsentSchema
  alias KlassHero.Participation.Adapters.Driven.Persistence.Schemas.BehavioralNoteSchema
  alias KlassHero.Participation.Adapters.Driven.Persistence.Schemas.ParticipationRecordSchema
  alias KlassHero.Repo

  describe "delete_child/1" do
    test "deletes existing child" do
      child_schema = insert(:child_schema)

      assert :ok = Family.delete_child(child_schema.id)
    end

    test "deletes child with associated consent records" do
      {child_schema, parent_schema} = insert_child_with_guardian()

      insert(:consent_schema,
        child_id: child_schema.id,
        parent_id: parent_schema.id
      )

      assert :ok = Family.delete_child(child_schema.id)

      assert Repo.all(from(c in ConsentSchema, where: c.child_id == ^child_schema.id)) == []
    end

    test "returns :not_found for non-existent child" do
      assert {:error, :not_found} = Family.delete_child(Ecto.UUID.generate())
    end

    test "deletes child with active enrollments (cancels enrollments)" do
      program = insert(:program_schema)
      {child, parent} = insert_child_with_guardian()

      enrollment =
        insert(:enrollment_schema,
          program_id: program.id,
          child_id: child.id,
          parent_id: parent.id,
          status: "confirmed"
        )

      assert :ok = Family.delete_child(child.id)

      # Enrollment should be cancelled, not deleted; child_id nullified by FK nilify_all
      updated = Repo.get(EnrollmentSchema, enrollment.id)
      assert updated.status == :cancelled
      assert is_nil(updated.child_id)
    end

    test "deletes child with participation records" do
      {child, parent} = insert_child_with_guardian()
      session = insert(:program_session_schema)

      insert(:participation_record_schema,
        child_id: child.id,
        parent_id: parent.id,
        session_id: session.id
      )

      assert :ok = Family.delete_child(child.id)

      assert [] = Repo.all(from(r in ParticipationRecordSchema, where: r.child_id == ^child.id))
    end

    test "deletes child with behavioral notes and participation records" do
      {child, parent} = insert_child_with_guardian()
      record = insert(:participation_record_schema, child_id: child.id, parent_id: parent.id)

      insert(:behavioral_note_schema,
        participation_record_id: record.id,
        child_id: child.id,
        parent_id: parent.id
      )

      assert :ok = Family.delete_child(child.id)

      assert [] = Repo.all(from(n in BehavioralNoteSchema, where: n.child_id == ^child.id))
      assert [] = Repo.all(from(r in ParticipationRecordSchema, where: r.child_id == ^child.id))
    end

    test "deletes child with enrollments, participation records, and consents" do
      program = insert(:program_schema)
      {child, parent} = insert_child_with_guardian()
      session = insert(:program_session_schema)

      insert(:enrollment_schema,
        program_id: program.id,
        child_id: child.id,
        parent_id: parent.id,
        status: "pending"
      )

      insert(:participation_record_schema,
        child_id: child.id,
        parent_id: parent.id,
        session_id: session.id
      )

      insert(:consent_schema,
        child_id: child.id,
        parent_id: parent.id
      )

      assert :ok = Family.delete_child(child.id)
    end
  end
end
