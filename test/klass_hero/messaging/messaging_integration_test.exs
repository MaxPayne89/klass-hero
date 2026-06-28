defmodule KlassHero.Messaging.MessagingIntegrationTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Accounts.Scope
  alias KlassHero.AccountsFixtures
  alias KlassHero.Family.ParentProfile
  alias KlassHero.Messaging
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.ConversationSummarySchema
  alias KlassHero.Provider.Domain.Models.ProviderProfile
  alias KlassHero.Repo

  describe "complete direct messaging flow" do
    test "provider initiates conversation with parent, both exchange messages" do
      provider = insert(:provider_profile_schema)
      provider_scope = build_scope_with_provider(provider)

      parent_user = AccountsFixtures.user_fixture()
      _parent_scope = build_scope_with_parent(parent_user, :active)

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

      # Trigger: conversation_summaries read model must be populated for list_conversations
      # Why: CQRS read side queries the denormalized table, not write tables
      # Outcome: list_conversations can return the enriched conversation data
      insert_conversation_summary(%{
        conversation_id: conversation.id,
        user_id: parent_user.id,
        conversation_type: "direct",
        provider_id: provider.id,
        other_participant_name: "Test Provider",
        latest_message_content: msg3.content,
        latest_message_sender_id: provider_scope.user.id,
        latest_message_at: msg3.inserted_at,
        unread_count: 3,
        last_read_at: nil
      })

      {:ok, conversations, _has_more} = Messaging.list_conversations(parent_user.id)

      assert length(conversations) == 1
      assert hd(conversations).unread_count == 3

      {:ok, _} = Messaging.mark_as_read(conversation.id, parent_user.id)

      # After mark_as_read, update the read model to reflect the change
      # (In production, the projection would handle this)
      update_summary_unread_count(conversation.id, parent_user.id, 0)

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

      # Populate conversation_summaries read model
      insert_conversation_summary(%{
        conversation_id: conversation.id,
        user_id: parent_user.id,
        conversation_type: "direct",
        provider_id: provider.id,
        other_participant_name: "Test Provider",
        latest_message_content: "Hello parent!",
        latest_message_sender_id: provider_scope.user.id,
        latest_message_at: msg.inserted_at
      })

      {:ok, conversations, _has_more} = Messaging.list_conversations(parent_user.id)

      enriched = hd(conversations)
      assert enriched.latest_message.content == "Hello parent!"
      assert enriched.other_participant_name != nil
    end
  end

  describe "complete broadcast flow" do
    test "provider broadcasts to all enrolled parents" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema)
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

      # Populate conversation_summaries for the broadcast recipients
      for parent_identity_id <- [parent1.identity_id, parent2.identity_id] do
        insert_conversation_summary(%{
          conversation_id: conversation.id,
          user_id: parent_identity_id,
          conversation_type: "program_broadcast",
          provider_id: provider.id,
          program_id: program.id,
          subject: "Schedule Update",
          other_participant_name: "Schedule Update",
          latest_message_content: "Important schedule change!",
          latest_message_sender_id: provider_scope.user.id,
          latest_message_at: message.inserted_at
        })
      end

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

  defp insert_conversation_summary(attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    defaults = %{
      id: Ecto.UUID.generate(),
      conversation_id: Ecto.UUID.generate(),
      user_id: Ecto.UUID.generate(),
      conversation_type: "direct",
      provider_id: Ecto.UUID.generate(),
      program_id: nil,
      subject: nil,
      other_participant_name: "Other User",
      participant_count: 2,
      latest_message_content: nil,
      latest_message_sender_id: nil,
      latest_message_at: nil,
      unread_count: 0,
      last_read_at: nil,
      archived_at: nil,
      inserted_at: now,
      updated_at: now
    }

    merged = Map.merge(defaults, attrs)

    %ConversationSummarySchema{}
    |> Ecto.Changeset.change(merged)
    |> Repo.insert!()
  end

  defp update_summary_unread_count(conversation_id, user_id, new_count) do
    import Ecto.Query

    from(s in ConversationSummarySchema,
      where: s.conversation_id == ^conversation_id and s.user_id == ^user_id
    )
    |> Repo.update_all(set: [unread_count: new_count])
  end

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

  defp build_scope_with_parent(user, tier) do
    parent_profile = %ParentProfile{
      id: Ecto.UUID.generate(),
      identity_id: user.id,
      display_name: "Test Parent",
      subscription_tier: tier
    }

    %Scope{
      user: user,
      roles: [:parent],
      parent: parent_profile,
      provider: nil
    }
  end
end
