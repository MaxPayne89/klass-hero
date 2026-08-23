defmodule KlassHero.Participation.ReviewSessionNoteTest do
  @moduledoc """
  Integration tests for ReviewSessionNote use case.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Accounts.Scope
  alias KlassHero.AccountsFixtures

  describe "execute/1 - approve" do
    test "approves a pending session note" do
      {child, parent} = insert_child_with_guardian()
      schema = insert(:session_note_schema, status: :pending_approval, child_id: child.id)
      scope = %Scope{user: AccountsFixtures.unconfirmed_user_fixture(), parent: parent}

      assert {:ok, note} =
               KlassHero.Participation.review_session_note(scope, %{
                 note_id: schema.id,
                 decision: :approve
               })

      assert note.status == :approved
      assert note.reviewed_at != nil
    end

    test "returns error for non-existent note" do
      assert {:error, :not_found} =
               KlassHero.Participation.review_session_note(%Scope{}, %{
                 note_id: Ecto.UUID.generate(),
                 decision: :approve
               })
    end

    test "returns error for already approved note" do
      {child, parent} = insert_child_with_guardian()

      schema =
        insert(:session_note_schema,
          status: :approved,
          child_id: child.id,
          reviewed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      scope = %Scope{user: AccountsFixtures.unconfirmed_user_fixture(), parent: parent}

      assert {:error, :invalid_status_transition} =
               KlassHero.Participation.review_session_note(scope, %{
                 note_id: schema.id,
                 decision: :approve
               })
    end

    test "returns unauthorized when parent_id does not match note owner" do
      schema = insert(:session_note_schema, status: :pending_approval)
      wrong_parent_id = Ecto.UUID.generate()

      scope = %Scope{
        user: AccountsFixtures.unconfirmed_user_fixture(),
        parent: %{id: wrong_parent_id}
      }

      assert {:error, :unauthorized} =
               KlassHero.Participation.review_session_note(scope, %{
                 note_id: schema.id,
                 decision: :approve
               })
    end

    test "returns unauthorized when the scope's parent's children do not include the note's child" do
      {child, _note_parent} = insert_child_with_guardian()
      schema = insert(:session_note_schema, status: :pending_approval, child_id: child.id)
      {_other_child, other_parent} = insert_child_with_guardian()
      scope = %Scope{user: AccountsFixtures.unconfirmed_user_fixture(), parent: other_parent}

      assert {:error, :unauthorized} =
               KlassHero.Participation.review_session_note(scope, %{
                 note_id: schema.id,
                 decision: :approve
               })
    end
  end

  describe "execute/1 - reject" do
    test "rejects a pending session note with reason" do
      {child, parent} = insert_child_with_guardian()
      schema = insert(:session_note_schema, status: :pending_approval, child_id: child.id)
      scope = %Scope{user: AccountsFixtures.unconfirmed_user_fixture(), parent: parent}

      assert {:ok, note} =
               KlassHero.Participation.review_session_note(scope, %{
                 note_id: schema.id,
                 decision: :reject,
                 reason: "Not accurate"
               })

      assert note.status == :rejected
      assert note.rejection_reason == "Not accurate"
      assert note.reviewed_at != nil
    end

    test "rejects a pending session note without reason" do
      {child, parent} = insert_child_with_guardian()
      schema = insert(:session_note_schema, status: :pending_approval, child_id: child.id)
      scope = %Scope{user: AccountsFixtures.unconfirmed_user_fixture(), parent: parent}

      assert {:ok, note} =
               KlassHero.Participation.review_session_note(scope, %{
                 note_id: schema.id,
                 decision: :reject
               })

      assert note.status == :rejected
      assert note.rejection_reason == nil
    end
  end
end
