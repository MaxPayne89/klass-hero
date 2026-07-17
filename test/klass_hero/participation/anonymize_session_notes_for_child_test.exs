defmodule KlassHero.Participation.AnonymizeSessionNotesForChildTest do
  @moduledoc """
  Tests for Participation.anonymize_session_notes_for_child/1.

  Verifies that session notes are bulk-anonymized for GDPR account deletion:
  content replaced, status set to rejected, rejection_reason cleared.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Participation
  alias KlassHero.Participation.SessionNote

  describe "anonymize_session_notes_for_child/1" do
    test "anonymizes all notes for a child" do
      note_a =
        insert(:session_note_schema,
          content: "Very engaged today",
          status: :approved
        )

      child_id = note_a.child_id

      note_b =
        insert(:session_note_schema,
          child_id: child_id,
          content: "Needs more focus",
          status: :pending_approval
        )

      {:ok, count} = Participation.anonymize_session_notes_for_child(child_id)

      assert count == 2

      reloaded_a = Repo.get!(SessionNote, note_a.id)
      reloaded_b = Repo.get!(SessionNote, note_b.id)

      assert reloaded_a.content == "[Removed - account deleted]"
      assert reloaded_a.status == :rejected
      assert is_nil(reloaded_a.rejection_reason)

      assert reloaded_b.content == "[Removed - account deleted]"
      assert reloaded_b.status == :rejected
      assert is_nil(reloaded_b.rejection_reason)
    end

    test "returns count of anonymized notes" do
      note = insert(:session_note_schema)

      {:ok, count} = Participation.anonymize_session_notes_for_child(note.child_id)

      assert count == 1
    end

    test "returns zero when no notes exist for child" do
      child_id = Ecto.UUID.generate()

      {:ok, count} = Participation.anonymize_session_notes_for_child(child_id)

      assert count == 0
    end
  end
end
