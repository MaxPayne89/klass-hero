defmodule KlassHero.Participation.Application.Queries.GetBehavioralNoteForRecordTest do
  @moduledoc """
  Integration tests for GetBehavioralNoteForRecord use case.

  Tests retrieval of behavioral notes by participation record and provider,
  covering both single-record and batch variants.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Participation.BehavioralNote

  describe "execute/2 - single note retrieval" do
    test "returns note when it exists for the given record and provider" do
      note_schema = insert(:behavioral_note_schema)

      assert {:ok, note} =
               KlassHero.Participation.get_behavioral_note_by_record_and_provider(
                 note_schema.participation_record_id,
                 note_schema.provider_id
               )

      assert %BehavioralNote{} = note
      assert note.id == note_schema.id
      assert note.participation_record_id == note_schema.participation_record_id
      assert note.provider_id == note_schema.provider_id
    end

    test "returns error when record id does not exist" do
      provider = insert(:provider_profile_schema)
      non_existent_record_id = Ecto.UUID.generate()

      assert {:error, :not_found} =
               KlassHero.Participation.get_behavioral_note_by_record_and_provider(non_existent_record_id, provider.id)
    end

    test "returns error when note belongs to a different provider" do
      note_schema = insert(:behavioral_note_schema)
      other_provider = insert(:provider_profile_schema)

      assert {:error, :not_found} =
               KlassHero.Participation.get_behavioral_note_by_record_and_provider(
                 note_schema.participation_record_id,
                 other_provider.id
               )
    end

    test "maps all domain fields from the persisted schema" do
      note_schema = insert(:behavioral_note_schema, content: "Excellent focus today")

      assert {:ok, note} =
               KlassHero.Participation.get_behavioral_note_by_record_and_provider(
                 note_schema.participation_record_id,
                 note_schema.provider_id
               )

      assert note.content == "Excellent focus today"
      assert note.status == :pending_approval
      assert note.child_id == note_schema.child_id
      assert note.parent_id == note_schema.parent_id
    end
  end

  describe "execute_batch/2 - batch note retrieval" do
    test "returns notes for all matching records" do
      note1 = insert(:behavioral_note_schema)

      # Share provider from first note so both belong to the same provider
      user = KlassHero.AccountsFixtures.unconfirmed_user_fixture()

      record2 =
        insert(:participation_record_schema,
          status: :checked_in,
          check_in_at: DateTime.utc_now(),
          check_in_by: user.id
        )

      note2 =
        insert(:behavioral_note_schema,
          participation_record_id: record2.id,
          child_id: record2.child_id,
          parent_id: record2.parent_id,
          provider_id: note1.provider_id
        )

      record_ids = [note1.participation_record_id, note2.participation_record_id]

      notes = KlassHero.Participation.list_behavioral_notes_by_records_and_provider(record_ids, note1.provider_id)

      assert length(notes) == 2
      returned_ids = Enum.map(notes, & &1.id) |> MapSet.new()
      assert MapSet.member?(returned_ids, note1.id)
      assert MapSet.member?(returned_ids, note2.id)
    end

    test "returns empty list when no records have notes" do
      user = KlassHero.AccountsFixtures.unconfirmed_user_fixture()
      record = insert(:participation_record_schema, check_in_by: user.id)
      provider = insert(:provider_profile_schema)

      notes = KlassHero.Participation.list_behavioral_notes_by_records_and_provider([record.id], provider.id)

      assert notes == []
    end

    test "returns empty list for empty record id list" do
      provider = insert(:provider_profile_schema)

      notes = KlassHero.Participation.list_behavioral_notes_by_records_and_provider([], provider.id)

      assert notes == []
    end

    test "excludes notes belonging to other providers" do
      note_schema = insert(:behavioral_note_schema)
      other_provider = insert(:provider_profile_schema)

      notes =
        KlassHero.Participation.list_behavioral_notes_by_records_and_provider(
          [note_schema.participation_record_id],
          other_provider.id
        )

      assert notes == []
    end

    test "returns only notes for given record ids, ignoring others" do
      note1 = insert(:behavioral_note_schema)
      _note2 = insert(:behavioral_note_schema, provider_id: note1.provider_id)

      # Only pass note1's record id
      notes =
        KlassHero.Participation.list_behavioral_notes_by_records_and_provider(
          [note1.participation_record_id],
          note1.provider_id
        )

      assert length(notes) == 1
      assert hd(notes).id == note1.id
    end

    test "returns domain BehavioralNote structs" do
      note_schema = insert(:behavioral_note_schema)

      [note] =
        KlassHero.Participation.list_behavioral_notes_by_records_and_provider(
          [note_schema.participation_record_id],
          note_schema.provider_id
        )

      assert %BehavioralNote{} = note
    end
  end
end
