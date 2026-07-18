defmodule KlassHero.Participation.GetApprovedSessionNotesTest do
  @moduledoc """
  Integration tests for GetApprovedSessionNotes use case.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  describe "execute/1" do
    test "returns approved notes for a child" do
      note = insert(:session_note_schema, status: :approved, reviewed_at: DateTime.utc_now())

      assert {:ok, notes} = KlassHero.Participation.get_approved_session_notes(note.child_id)
      assert length(notes) == 1
      assert hd(notes).id == note.id
      assert hd(notes).status == :approved
    end

    test "filters out pending and rejected notes" do
      # Create a shared child + record so all notes reference the same child_id
      staff_user = KlassHero.AccountsFixtures.unconfirmed_user_fixture()

      record =
        insert(:participation_record_schema,
          status: :checked_in,
          check_in_at: DateTime.utc_now(),
          check_in_by: staff_user.id
        )

      child_id = record.child_id

      insert(:session_note_schema,
        participation_record_id: record.id,
        child_id: child_id,
        parent_id: record.parent_id,
        status: :approved,
        reviewed_at: DateTime.utc_now()
      )

      # Create separate records for the other notes (unique constraint: one note per provider per record)
      record2 =
        insert(:participation_record_schema,
          child_id: child_id,
          parent_id: record.parent_id,
          status: :checked_in,
          check_in_at: DateTime.utc_now(),
          check_in_by: staff_user.id
        )

      insert(:session_note_schema,
        participation_record_id: record2.id,
        child_id: child_id,
        parent_id: record.parent_id,
        status: :pending_approval
      )

      record3 =
        insert(:participation_record_schema,
          child_id: child_id,
          parent_id: record.parent_id,
          status: :checked_in,
          check_in_at: DateTime.utc_now(),
          check_in_by: staff_user.id
        )

      insert(:session_note_schema,
        participation_record_id: record3.id,
        child_id: child_id,
        parent_id: record.parent_id,
        status: :rejected,
        rejection_reason: "Please rephrase",
        reviewed_at: DateTime.utc_now()
      )

      assert {:ok, notes} = KlassHero.Participation.get_approved_session_notes(child_id)
      assert length(notes) == 1
      assert hd(notes).status == :approved
    end

    test "returns {:ok, []} for nonexistent child" do
      assert {:ok, []} = KlassHero.Participation.get_approved_session_notes(Ecto.UUID.generate())
    end
  end
end
