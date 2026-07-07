defmodule KlassHero.Messaging.StartProgramConversationTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Accounts.Scope
  alias KlassHero.AccountsFixtures
  alias KlassHero.Family.ParentProfile
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.ProgramStaffParticipantRepository
  alias KlassHero.Messaging.Conversation
  alias KlassHero.Messaging.StartProgramConversation

  describe "execute/3" do
    test "creates a direct conversation with provider owner and assigned staff as participants" do
      owner = AccountsFixtures.user_fixture()
      provider = insert(:provider_profile_schema, identity_id: owner.id)
      program = insert(:program_schema, provider_id: provider.id)
      staff_user = AccountsFixtures.user_fixture()

      ProgramStaffParticipantRepository.upsert_active(%{
        provider_id: provider.id,
        program_id: program.id,
        staff_user_id: staff_user.id
      })

      parent_scope = build_scope_with_parent()

      assert {:ok, conversation} =
               StartProgramConversation.execute(parent_scope, provider.id, program.id)

      assert %Conversation{type: :direct} = conversation
      assert conversation.provider_id == provider.id
      assert conversation.program_id == program.id
      assert KlassHero.Messaging.participant?(conversation.id, parent_scope.user.id)
      assert KlassHero.Messaging.participant?(conversation.id, owner.id)
      assert KlassHero.Messaging.participant?(conversation.id, staff_user.id)
    end

    test "returns existing conversation on repeat call" do
      owner = AccountsFixtures.user_fixture()
      provider = insert(:provider_profile_schema, identity_id: owner.id)
      program = insert(:program_schema, provider_id: provider.id)
      parent_scope = build_scope_with_parent()

      assert {:ok, first} =
               StartProgramConversation.execute(parent_scope, provider.id, program.id)

      assert {:ok, second} =
               StartProgramConversation.execute(parent_scope, provider.id, program.id)

      assert first.id == second.id
    end

    test "returns not_found when provider does not exist" do
      parent_scope = build_scope_with_parent()

      assert {:error, :not_found} =
               StartProgramConversation.execute(
                 parent_scope,
                 Ecto.UUID.generate(),
                 Ecto.UUID.generate()
               )
    end
  end

  describe "cross-parent isolation" do
    test "two parents contacting the same provider get distinct conversations" do
      owner = AccountsFixtures.user_fixture()
      provider = insert(:provider_profile_schema, identity_id: owner.id)
      program = insert(:program_schema, provider_id: provider.id)
      parent_a_scope = build_scope_with_parent()
      parent_b_scope = build_scope_with_parent()

      assert {:ok, conv_a} =
               StartProgramConversation.execute(parent_a_scope, provider.id, program.id)

      assert {:ok, conv_b} =
               StartProgramConversation.execute(parent_b_scope, provider.id, program.id)

      assert conv_a.id != conv_b.id

      assert KlassHero.Messaging.participant?(conv_a.id, parent_a_scope.user.id)
      refute KlassHero.Messaging.participant?(conv_a.id, parent_b_scope.user.id)

      assert KlassHero.Messaging.participant?(conv_b.id, parent_b_scope.user.id)
      refute KlassHero.Messaging.participant?(conv_b.id, parent_a_scope.user.id)
    end
  end

  defp build_scope_with_parent do
    user = AccountsFixtures.user_fixture()

    parent_profile = %ParentProfile{
      id: Ecto.UUID.generate(),
      identity_id: user.id,
      display_name: "Test Parent"
    }

    %Scope{
      user: user,
      roles: [:parent],
      parent: parent_profile,
      provider: nil
    }
  end
end
