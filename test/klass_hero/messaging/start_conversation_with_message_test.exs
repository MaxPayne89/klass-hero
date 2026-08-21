defmodule KlassHero.Messaging.StartConversationWithMessageTest do
  use KlassHero.DataCase, async: false

  import Ecto.Query
  import KlassHero.EventTestHelper
  import KlassHero.Factory

  alias KlassHero.Accounts.Scope
  alias KlassHero.AccountsFixtures
  alias KlassHero.Family.ParentProfile
  alias KlassHero.Messaging.Conversation
  alias KlassHero.Messaging.Message
  alias KlassHero.Messaging.Participant
  alias KlassHero.Messaging.StartConversationWithMessage
  alias KlassHero.Provider.ProviderProfile
  alias KlassHero.Repo

  setup do
    setup_test_integration_events()
    :ok
  end

  describe "execute/5" do
    test "creates the conversation and its first message together" do
      provider = insert(:provider_profile_schema)
      scope = build_scope_with_provider(provider)
      target_user = AccountsFixtures.user_fixture()

      assert {:ok, %Conversation{} = conversation, %Message{} = message} =
               StartConversationWithMessage.execute(scope, provider.id, target_user.id, "Hello there")

      assert conversation.type == :direct
      assert conversation.provider_id == provider.id
      assert message.conversation_id == conversation.id
      assert message.content == "Hello there"
      assert participant_ids(conversation.id) == Enum.sort([scope.user.id, target_user.id])

      assert_integration_event_published(:conversation_created)
      assert_integration_event_published(:message_sent)
    end

    test "reuses an existing conversation rather than creating a second" do
      provider = insert(:provider_profile_schema)
      scope = build_scope_with_provider(provider)
      target_user = AccountsFixtures.user_fixture()

      assert {:ok, first, _} =
               StartConversationWithMessage.execute(scope, provider.id, target_user.id, "One")

      assert {:ok, second, _} =
               StartConversationWithMessage.execute(scope, provider.id, target_user.id, "Two")

      assert first.id == second.id
      assert conversation_count() == 1
    end

    test "rejects a blank message without creating a conversation" do
      provider = insert(:provider_profile_schema)
      scope = build_scope_with_provider(provider)
      target_user = AccountsFixtures.user_fixture()

      assert {:error, :empty_message} =
               StartConversationWithMessage.execute(scope, provider.id, target_user.id, "   ")

      assert conversation_count() == 0
    end

    test "rejects an unentitled scope without creating a conversation" do
      provider = insert(:provider_profile_schema)
      target_user = AccountsFixtures.user_fixture()
      scope = %Scope{user: AccountsFixtures.user_fixture(), parent: nil, provider: nil}

      assert {:error, :not_entitled} =
               StartConversationWithMessage.execute(scope, provider.id, target_user.id, "Hello")

      assert conversation_count() == 0
    end

    test "accepts an attachments-only first message" do
      provider = insert(:provider_profile_schema)
      scope = build_scope_with_provider(provider)
      target_user = AccountsFixtures.user_fixture()

      attachment = %{
        binary: "fake-image-bytes",
        filename: "photo.jpg",
        content_type: "image/jpeg",
        size: 16
      }

      assert {:ok, _conversation, %Message{} = message} =
               StartConversationWithMessage.execute(scope, provider.id, target_user.id, nil, attachments: [attachment])

      assert message.attachments != []
    end

    test "a parent initiating about a program reaches the provider owner" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      scope = build_scope_with_parent()

      assert {:ok, conversation, message} =
               StartConversationWithMessage.execute(
                 scope,
                 provider.id,
                 nil,
                 "Question about the program",
                 program_id: program.id
               )

      assert conversation.program_id == program.id
      assert message.sender_id == scope.user.id
      assert provider.identity_id in participant_ids(conversation.id)
    end
  end

  defp conversation_count, do: Repo.aggregate(Conversation, :count, :id)

  defp participant_ids(conversation_id) do
    from(p in Participant, where: p.conversation_id == ^conversation_id, select: p.user_id)
    |> Repo.all()
    |> Enum.sort()
  end

  defp build_scope_with_provider(provider_schema) do
    user = AccountsFixtures.user_fixture()

    %Scope{
      user: user,
      roles: [:provider],
      provider: %ProviderProfile{
        id: provider_schema.id,
        identity_id: user.id,
        business_name: "Test Provider"
      },
      parent: nil
    }
  end

  defp build_scope_with_parent do
    user = AccountsFixtures.user_fixture()

    %Scope{
      user: user,
      roles: [:parent],
      parent: %ParentProfile{
        id: Ecto.UUID.generate(),
        identity_id: user.id,
        display_name: "Test Parent"
      },
      provider: nil
    }
  end
end
