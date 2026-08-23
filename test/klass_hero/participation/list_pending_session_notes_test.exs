defmodule KlassHero.Participation.ListPendingSessionNotesTest do
  @moduledoc """
  Integration tests for ListPendingSessionNotes use case.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  # A parent's notes are found through their children, not through
  # `session_notes.parent_id` — nothing populates that column (#1329). So every
  # fixture here has to hang a note off a child that the parent actually guards.
  describe "list_pending_session_notes/1" do
    test "returns pending notes for a parent" do
      {child, parent} = insert_child_with_guardian()
      note = insert(:session_note_schema, child_id: child.id, status: :pending_approval)

      assert {:ok, notes} = KlassHero.Participation.list_pending_session_notes(parent.id)
      assert length(notes) == 1
      assert hd(notes).id == note.id
      assert hd(notes).status == :pending_approval
    end

    test "filters out approved and rejected notes" do
      {child, parent} = insert_child_with_guardian()

      insert(:session_note_schema, child_id: child.id, status: :pending_approval)

      insert(:session_note_schema,
        child_id: child.id,
        status: :approved,
        reviewed_at: DateTime.utc_now()
      )

      insert(:session_note_schema,
        child_id: child.id,
        status: :rejected,
        rejection_reason: "Please rephrase",
        reviewed_at: DateTime.utc_now()
      )

      assert {:ok, notes} = KlassHero.Participation.list_pending_session_notes(parent.id)
      assert length(notes) == 1
      assert hd(notes).status == :pending_approval
    end

    test "excludes a pending note about another parent's child" do
      {_child, parent} = insert_child_with_guardian()
      {other_child, _other_parent} = insert_child_with_guardian()

      insert(:session_note_schema, child_id: other_child.id, status: :pending_approval)

      assert {:ok, []} = KlassHero.Participation.list_pending_session_notes(parent.id)
    end

    test "returns {:ok, []} for nonexistent parent" do
      assert {:ok, []} = KlassHero.Participation.list_pending_session_notes(Ecto.UUID.generate())
    end
  end
end
