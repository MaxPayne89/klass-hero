defmodule KlassHero.Participation.ReviseSessionNoteTest do
  @moduledoc """
  Integration tests for ReviseSessionNote use case.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Accounts.Scope
  alias KlassHero.AccountsFixtures
  alias KlassHero.ProviderFixtures

  describe "execute/1" do
    test "revises a rejected session note" do
      provider = ProviderFixtures.provider_profile_fixture()

      schema =
        insert(:session_note_schema,
          status: :rejected,
          provider_id: provider.id,
          rejection_reason: "Please rephrase",
          reviewed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      scope = %Scope{user: AccountsFixtures.unconfirmed_user_fixture(), provider: provider}

      assert {:ok, note} =
               KlassHero.Participation.revise_session_note(scope, %{
                 note_id: schema.id,
                 content: "Updated observation about the child"
               })

      assert note.status == :pending_approval
      assert note.content == "Updated observation about the child"
      assert note.rejection_reason == nil
    end

    test "a staff member of the authoring provider may also revise" do
      provider = ProviderFixtures.provider_profile_fixture()
      staff = ProviderFixtures.staff_member_fixture(%{provider_id: provider.id})

      schema =
        insert(:session_note_schema,
          status: :rejected,
          provider_id: provider.id,
          rejection_reason: "Please rephrase",
          reviewed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      scope = %Scope{user: AccountsFixtures.unconfirmed_user_fixture(), staff_member: staff}

      assert {:ok, note} =
               KlassHero.Participation.revise_session_note(scope, %{
                 note_id: schema.id,
                 content: "Revised by the assigned staff member"
               })

      assert note.status == :pending_approval
      assert note.content == "Revised by the assigned staff member"
    end

    test "returns error for non-existent note" do
      assert {:error, :not_found} =
               KlassHero.Participation.revise_session_note(%Scope{}, %{
                 note_id: Ecto.UUID.generate(),
                 content: "Some content"
               })
    end

    test "returns error for pending note" do
      provider = ProviderFixtures.provider_profile_fixture()
      schema = insert(:session_note_schema, status: :pending_approval, provider_id: provider.id)
      scope = %Scope{user: AccountsFixtures.unconfirmed_user_fixture(), provider: provider}

      assert {:error, :invalid_status_transition} =
               KlassHero.Participation.revise_session_note(scope, %{
                 note_id: schema.id,
                 content: "Updated"
               })
    end

    test "returns error for approved note" do
      provider = ProviderFixtures.provider_profile_fixture()

      schema =
        insert(:session_note_schema,
          status: :approved,
          provider_id: provider.id,
          reviewed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      scope = %Scope{user: AccountsFixtures.unconfirmed_user_fixture(), provider: provider}

      assert {:error, :invalid_status_transition} =
               KlassHero.Participation.revise_session_note(scope, %{
                 note_id: schema.id,
                 content: "Updated"
               })
    end

    test "returns error for blank content" do
      assert {:error, :blank_content} =
               KlassHero.Participation.revise_session_note(%Scope{}, %{
                 note_id: Ecto.UUID.generate(),
                 content: "  "
               })
    end

    test "returns unauthorized when provider_id does not match note owner" do
      schema =
        insert(:session_note_schema,
          status: :rejected,
          rejection_reason: "reason",
          reviewed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      other_provider = ProviderFixtures.provider_profile_fixture()
      scope = %Scope{user: AccountsFixtures.unconfirmed_user_fixture(), provider: other_provider}

      assert {:error, :unauthorized} =
               KlassHero.Participation.revise_session_note(scope, %{
                 note_id: schema.id,
                 content: "Updated observation"
               })
    end
  end
end
