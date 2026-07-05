defmodule KlassHero.Participation.SubmitBehavioralNoteTest do
  @moduledoc """
  Integration tests for SubmitBehavioralNote use case.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  describe "execute/1" do
    test "submits a behavioral note for a checked-in record" do
      staff_user = KlassHero.AccountsFixtures.unconfirmed_user_fixture()

      record =
        insert(:participation_record_schema,
          status: :checked_in,
          check_in_at: DateTime.utc_now(),
          check_in_by: staff_user.id
        )

      provider_id = insert(:provider_profile_schema).id

      assert {:ok, note} =
               KlassHero.Participation.submit_behavioral_note(%{
                 participation_record_id: record.id,
                 provider_id: provider_id,
                 content: "Child was very engaged today"
               })

      assert note.status == :pending_approval
      assert note.content == "Child was very engaged today"
      assert note.child_id == record.child_id
      assert note.parent_id == record.parent_id
      assert note.provider_id == provider_id
    end

    test "submits a behavioral note for a checked-out record" do
      staff_user = KlassHero.AccountsFixtures.unconfirmed_user_fixture()

      record =
        insert(:participation_record_schema,
          status: :checked_out,
          check_in_at: DateTime.add(DateTime.utc_now(), -3600, :second),
          check_in_by: staff_user.id,
          check_out_at: DateTime.utc_now(),
          check_out_by: staff_user.id
        )

      assert {:ok, note} =
               KlassHero.Participation.submit_behavioral_note(%{
                 participation_record_id: record.id,
                 provider_id: insert(:provider_profile_schema).id,
                 content: "Well behaved"
               })

      assert note.status == :pending_approval
    end

    test "returns error for registered record" do
      record = insert(:participation_record_schema, status: :registered)

      assert {:error, :invalid_record_status} =
               KlassHero.Participation.submit_behavioral_note(%{
                 participation_record_id: record.id,
                 provider_id: Ecto.UUID.generate(),
                 content: "Some note"
               })
    end

    test "returns error for absent record" do
      record = insert(:participation_record_schema, status: :absent)

      assert {:error, :invalid_record_status} =
               KlassHero.Participation.submit_behavioral_note(%{
                 participation_record_id: record.id,
                 provider_id: Ecto.UUID.generate(),
                 content: "Some note"
               })
    end

    test "returns error for non-existent record" do
      assert {:error, :not_found} =
               KlassHero.Participation.submit_behavioral_note(%{
                 participation_record_id: Ecto.UUID.generate(),
                 provider_id: Ecto.UUID.generate(),
                 content: "Some note"
               })
    end

    test "returns error for blank content" do
      record =
        insert(:participation_record_schema,
          status: :checked_in,
          check_in_at: DateTime.utc_now(),
          check_in_by: KlassHero.AccountsFixtures.unconfirmed_user_fixture().id
        )

      assert {:error, :blank_content} =
               KlassHero.Participation.submit_behavioral_note(%{
                 participation_record_id: record.id,
                 provider_id: Ecto.UUID.generate(),
                 content: "   "
               })
    end

    test "returns error for duplicate note from same provider" do
      record =
        insert(:participation_record_schema,
          status: :checked_in,
          check_in_at: DateTime.utc_now(),
          check_in_by: KlassHero.AccountsFixtures.unconfirmed_user_fixture().id
        )

      provider_id = insert(:provider_profile_schema).id

      assert {:ok, _} =
               KlassHero.Participation.submit_behavioral_note(%{
                 participation_record_id: record.id,
                 provider_id: provider_id,
                 content: "First note"
               })

      assert {:error, :duplicate_note} =
               KlassHero.Participation.submit_behavioral_note(%{
                 participation_record_id: record.id,
                 provider_id: provider_id,
                 content: "Second note"
               })
    end
  end
end
