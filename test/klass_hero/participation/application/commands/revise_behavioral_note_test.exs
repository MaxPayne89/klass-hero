defmodule KlassHero.Participation.Application.Commands.ReviseBehavioralNoteTest do
  @moduledoc """
  Integration tests for ReviseBehavioralNote use case.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  describe "execute/1" do
    test "revises a rejected behavioral note" do
      schema =
        insert(:behavioral_note_schema,
          status: :rejected,
          rejection_reason: "Please rephrase",
          reviewed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      assert {:ok, note} =
               KlassHero.Participation.revise_behavioral_note(%{
                 note_id: schema.id,
                 provider_id: schema.provider_id,
                 content: "Updated observation about the child"
               })

      assert note.status == :pending_approval
      assert note.content == "Updated observation about the child"
      assert note.rejection_reason == nil
    end

    test "returns error for non-existent note" do
      assert {:error, :not_found} =
               KlassHero.Participation.revise_behavioral_note(%{
                 note_id: Ecto.UUID.generate(),
                 provider_id: Ecto.UUID.generate(),
                 content: "Some content"
               })
    end

    test "returns error for pending note" do
      schema = insert(:behavioral_note_schema, status: :pending_approval)

      assert {:error, :invalid_status_transition} =
               KlassHero.Participation.revise_behavioral_note(%{
                 note_id: schema.id,
                 provider_id: schema.provider_id,
                 content: "Updated"
               })
    end

    test "returns error for approved note" do
      schema =
        insert(:behavioral_note_schema,
          status: :approved,
          reviewed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      assert {:error, :invalid_status_transition} =
               KlassHero.Participation.revise_behavioral_note(%{
                 note_id: schema.id,
                 provider_id: schema.provider_id,
                 content: "Updated"
               })
    end

    test "returns error for blank content" do
      schema =
        insert(:behavioral_note_schema,
          status: :rejected,
          rejection_reason: "reason",
          reviewed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      assert {:error, :blank_content} =
               KlassHero.Participation.revise_behavioral_note(%{
                 note_id: schema.id,
                 provider_id: schema.provider_id,
                 content: "  "
               })
    end

    test "returns not_found when provider_id does not match note owner" do
      schema =
        insert(:behavioral_note_schema,
          status: :rejected,
          rejection_reason: "reason",
          reviewed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      wrong_provider_id = Ecto.UUID.generate()

      assert {:error, :not_found} =
               KlassHero.Participation.revise_behavioral_note(%{
                 note_id: schema.id,
                 provider_id: wrong_provider_id,
                 content: "Updated observation"
               })
    end
  end
end
