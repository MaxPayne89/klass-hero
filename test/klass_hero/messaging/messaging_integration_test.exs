defmodule KlassHero.Messaging.MessagingIntegrationTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Accounts.Scope
  alias KlassHero.AccountsFixtures
  alias KlassHero.Family.ParentProfile
  alias KlassHero.Messaging
  alias KlassHero.Provider.ProviderProfile

  describe "complete direct messaging flow" do
    test "provider initiates conversation with parent, both exchange messages" do
      provider = insert(:provider_profile_schema)
      provider_scope = build_scope_with_provider(provider)

      parent_user = AccountsFixtures.user_fixture()
      _parent_scope = build_scope_with_parent(parent_user)

      assert {:ok, conversation} =
               Messaging.create_direct_conversation(
                 provider_scope,
                 provider.id,
                 parent_user.id
               )

      assert conversation.type == :direct

      assert {:ok, msg1} =
               Messaging.send_message(
                 conversation.id,
                 provider_scope.user.id,
                 "Hi! Your child is doing great!"
               )

      assert msg1.content == "Hi! Your child is doing great!"

      assert {:ok, msg2} =
               Messaging.send_message(
                 conversation.id,
                 parent_user.id,
                 "Thank you for the update!"
               )

      assert msg2.content == "Thank you for the update!"

      assert {:ok, result} = Messaging.get_conversation(conversation.id, parent_user.id)

      assert length(result.messages) == 2
    end

    test "unread tracking works correctly" do
      provider = insert(:provider_profile_schema)
      provider_scope = build_scope_with_provider(provider)

      parent_user = AccountsFixtures.user_fixture()

      {:ok, conversation} =
        Messaging.create_direct_conversation(provider_scope, provider.id, parent_user.id)

      Messaging.send_message(conversation.id, provider_scope.user.id, "Message 1")
      Messaging.send_message(conversation.id, provider_scope.user.id, "Message 2")
      {:ok, msg3} = Messaging.send_message(conversation.id, provider_scope.user.id, "Message 3")

      # The three messages above are the whole fixture: the inbox reads them
      # directly, so there is no read model to populate first.
      assert msg3.content == "Message 3"

      {:ok, conversations, _has_more} = Messaging.list_conversations(parent_user.id)

      assert length(conversations) == 1
      assert hd(conversations).unread_count == 3

      {:ok, _} = Messaging.mark_as_read(conversation.id, parent_user.id)

      {:ok, conversations, _has_more} = Messaging.list_conversations(parent_user.id)
      assert hd(conversations).unread_count == 0
    end

    test "listing conversations shows latest message and other participant name" do
      provider = insert(:provider_profile_schema)
      provider_scope = build_scope_with_provider(provider)

      parent_user = AccountsFixtures.user_fixture()

      {:ok, conversation} =
        Messaging.create_direct_conversation(provider_scope, provider.id, parent_user.id)

      {:ok, msg} =
        Messaging.send_message(conversation.id, provider_scope.user.id, "Hello parent!")

      assert msg.content == "Hello parent!"

      {:ok, conversations, _has_more} = Messaging.list_conversations(parent_user.id)

      summary = hd(conversations)
      assert summary.latest_message_content == "Hello parent!"

      # Read live from Accounts rather than copied at conversation-creation time,
      # so it is the provider's actual name and cannot go stale.
      assert summary.other_participant_name == provider_scope.user.name
    end
  end

  describe "complete broadcast flow" do
    test "provider broadcasts to all enrolled parents" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      provider_scope = build_scope_with_provider(provider)

      # Create parents with real users to satisfy FK constraint
      parent_user1 = AccountsFixtures.user_fixture()
      parent_user2 = AccountsFixtures.user_fixture()
      parent_user3 = AccountsFixtures.user_fixture()
      parent1 = insert(:parent_profile_schema, identity_id: parent_user1.id)
      parent2 = insert(:parent_profile_schema, identity_id: parent_user2.id)
      parent3 = insert(:parent_profile_schema, identity_id: parent_user3.id)

      insert(:enrollment_schema,
        program_id: program.id,
        parent_id: parent1.id,
        status: "confirmed"
      )

      insert(:enrollment_schema,
        program_id: program.id,
        parent_id: parent2.id,
        status: "pending"
      )

      insert(:enrollment_schema,
        program_id: program.id,
        parent_id: parent3.id,
        status: "cancelled"
      )

      assert {:ok, conversation, message, recipient_count} =
               Messaging.broadcast_to_program(
                 provider_scope,
                 program.id,
                 "Important schedule change!",
                 subject: "Schedule Update"
               )

      assert conversation.type == :program_broadcast
      assert conversation.subject == "Schedule Update"
      assert message.content == "Important schedule change!"
      assert recipient_count == 2

      # The broadcast seated both parents and wrote the message, which is all the
      # inbox needs — it derives the rest.
      {:ok, conversations, _} = Messaging.list_conversations(parent1.identity_id)
      assert conversations != []

      {:ok, conversations, _} = Messaging.list_conversations(parent2.identity_id)
      assert conversations != []
    end
  end

  describe "PubSub integration" do
    test "subscribing to conversation topic works" do
      conversation = insert(:conversation_schema)

      assert :ok = Messaging.subscribe_to_conversation(conversation.id)
    end

    test "subscribing to user messages topic works" do
      user = AccountsFixtures.user_fixture()

      assert :ok = Messaging.subscribe_to_user_messages(user.id)
    end
  end

  # --- Helpers ---

  defp build_scope_with_provider(provider_schema) do
    user = AccountsFixtures.user_fixture()

    # Trigger: factory binds provider row to a throwaway unconfirmed user
    # Why: SendMessage's provider_owner? check compares scope.user.id against the
    #      provider row's identity_id; mismatch surfaces as :broadcast_reply_not_allowed
    # Outcome: rebind the row to our confirmed user so ownership checks pass
    {:ok, _} =
      provider_schema
      |> Ecto.Changeset.change(identity_id: user.id)
      |> KlassHero.Repo.update()

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

  defp build_scope_with_parent(user) do
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
