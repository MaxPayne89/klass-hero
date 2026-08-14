defmodule KlassHero.Messaging.CreateDirectConversationTest do
  use KlassHero.DataCase, async: false

  import KlassHero.EventTestHelper
  import KlassHero.Factory

  alias KlassHero.Accounts.Scope
  alias KlassHero.AccountsFixtures
  alias KlassHero.Family.ParentProfile
  alias KlassHero.Messaging.Conversation
  alias KlassHero.Messaging.CreateDirectConversation
  alias KlassHero.Provider.ProviderProfile
  alias KlassHero.ProviderFixtures

  describe "execute/3" do
    test "creates new conversation with participants" do
      provider = insert(:provider_profile_schema)
      scope = build_scope_with_provider(provider)

      target_user = AccountsFixtures.user_fixture()

      assert {:ok, conversation} =
               CreateDirectConversation.execute(scope, provider.id, target_user.id)

      assert %Conversation{} = conversation
      assert conversation.type == :direct
      assert conversation.provider_id == provider.id
    end

    test "returns existing conversation if one already exists" do
      provider = insert(:provider_profile_schema)
      scope = build_scope_with_provider(provider)

      target_user = AccountsFixtures.user_fixture()

      assert {:ok, first_conversation} =
               CreateDirectConversation.execute(scope, provider.id, target_user.id)

      assert {:ok, second_conversation} =
               CreateDirectConversation.execute(scope, provider.id, target_user.id)

      assert first_conversation.id == second_conversation.id
    end

    test "provider can initiate" do
      provider = insert(:provider_profile_schema)
      scope = build_scope_with_provider(provider)

      target_user = AccountsFixtures.user_fixture()

      assert {:ok, _conversation} =
               CreateDirectConversation.execute(scope, provider.id, target_user.id)
    end

    test "parent can initiate" do
      provider = insert(:provider_profile_schema)
      scope = build_scope_with_parent()

      target_user = AccountsFixtures.user_fixture()

      assert {:ok, _conversation} =
               CreateDirectConversation.execute(scope, provider.id, target_user.id)
    end
  end

  describe "staff auto-inclusion" do
    setup do
      setup_test_integration_events()
      :ok
    end

    test "adds assigned staff as participants when conversation has program context" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      scope = build_scope_with_provider(provider)
      target_user = AccountsFixtures.user_fixture()
      staff_user = AccountsFixtures.user_fixture()

      ProviderFixtures.assign_active_staff(%{
        provider_id: provider.id,
        program_id: program.id,
        staff_user_id: staff_user.id
      })

      assert {:ok, conversation} =
               CreateDirectConversation.execute(scope, provider.id, target_user.id, program_id: program.id)

      assert KlassHero.Messaging.participant?(conversation.id, staff_user.id)
    end

    test "publishes :participant_added integration event when staff are added" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      scope = build_scope_with_provider(provider)
      target_user = AccountsFixtures.user_fixture()
      staff_user = AccountsFixtures.user_fixture()

      ProviderFixtures.assign_active_staff(%{
        provider_id: provider.id,
        program_id: program.id,
        staff_user_id: staff_user.id
      })

      assert {:ok, conversation} =
               CreateDirectConversation.execute(
                 scope,
                 provider.id,
                 target_user.id,
                 program_id: program.id
               )

      event = assert_integration_event_published(:participant_added)
      assert event.entity_id == conversation.id
      assert event.payload.participant_user_ids == [staff_user.id]
      assert event.payload.source == :initial_staff
    end

    test "does not add staff when no program_id provided" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      scope = build_scope_with_provider(provider)
      target_user = AccountsFixtures.user_fixture()
      staff_user = AccountsFixtures.user_fixture()

      ProviderFixtures.assign_active_staff(%{
        provider_id: provider.id,
        program_id: program.id,
        staff_user_id: staff_user.id
      })

      assert {:ok, conversation} =
               CreateDirectConversation.execute(scope, provider.id, target_user.id)

      refute KlassHero.Messaging.participant?(conversation.id, staff_user.id)
    end

    test "does not add owner as duplicate staff participant" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      scope = build_scope_with_provider(provider)
      target_user = AccountsFixtures.user_fixture()

      # The owner (scope.user) is also assigned as staff
      ProviderFixtures.assign_active_staff(%{
        provider_id: provider.id,
        program_id: program.id,
        staff_user_id: scope.user.id
      })

      assert {:ok, _conversation} =
               CreateDirectConversation.execute(scope, provider.id, target_user.id, program_id: program.id)
    end

    test "does not add staff to existing conversations" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      scope = build_scope_with_provider(provider)
      target_user = AccountsFixtures.user_fixture()

      # First create the conversation without staff
      assert {:ok, first_conversation} =
               CreateDirectConversation.execute(scope, provider.id, target_user.id)

      # Now assign staff
      staff_user = AccountsFixtures.user_fixture()

      ProviderFixtures.assign_active_staff(%{
        provider_id: provider.id,
        program_id: program.id,
        staff_user_id: staff_user.id
      })

      # Calling again returns the existing conversation without adding staff
      assert {:ok, second_conversation} =
               CreateDirectConversation.execute(scope, provider.id, target_user.id, program_id: program.id)

      assert first_conversation.id == second_conversation.id
      refute KlassHero.Messaging.participant?(second_conversation.id, staff_user.id)
    end
  end

  defp build_scope_with_provider(provider_schema) do
    user = AccountsFixtures.user_fixture()

    provider_profile = %ProviderProfile{
      id: provider_schema.id,
      identity_id: user.id,
      business_name: "Test Provider"
    }

    %Scope{
      user: user,
      roles: [:provider],
      provider: provider_profile,
      parent: nil
    }
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
