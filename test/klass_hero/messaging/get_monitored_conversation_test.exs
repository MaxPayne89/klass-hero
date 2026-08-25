defmodule KlassHero.Messaging.GetMonitoredConversationTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.AccountsFixtures
  alias KlassHero.Messaging
  alias KlassHero.Messaging.Conversation
  alias KlassHero.Messaging.GetMonitoredConversation
  alias KlassHero.Messaging.Participant

  defp admin_scope, do: AccountsFixtures.admin_scope_fixture()

  defp conversation_with_message do
    conversation = insert(:conversation_schema)
    parent = AccountsFixtures.user_fixture()

    insert(:participant_schema, conversation_id: conversation.id, user_id: parent.id)

    {:ok, _message} =
      Messaging.create_message(%{
        conversation_id: conversation.id,
        sender_id: parent.id,
        content: "Private message about my child"
      })

    %{conversation: conversation, parent: parent}
  end

  describe "execute/3 authorization" do
    test "refuses a non-admin scope" do
      %{conversation: conversation} = conversation_with_message()

      assert {:error, :unauthorized} =
               GetMonitoredConversation.execute(
                 AccountsFixtures.user_scope_fixture(),
                 conversation.id
               )
    end

    test "refuses a non-admin scope before looking at the conversation id" do
      assert {:error, :unauthorized} =
               GetMonitoredConversation.execute(
                 AccountsFixtures.user_scope_fixture(),
                 Ecto.UUID.generate()
               )
    end

    test "returns not_found for an admin asking for a conversation that does not exist" do
      assert {:error, :not_found} =
               GetMonitoredConversation.execute(admin_scope(), Ecto.UUID.generate())
    end
  end

  describe "execute/3 reading" do
    test "returns the thread of a conversation the admin is not a participant of" do
      %{conversation: conversation} = conversation_with_message()
      scope = admin_scope()

      refute Messaging.participant?(conversation.id, scope.user.id)

      assert {:ok, result} = GetMonitoredConversation.execute(scope, conversation.id)

      assert %Conversation{id: id} = result.conversation
      assert id == conversation.id
      assert [message] = result.messages
      assert message.content == "Private message about my child"
      assert is_map(result.sender_names)
      assert is_boolean(result.has_more)
    end
  end

  describe "execute/3 is strictly read-only" do
    test "creates no participant row for the admin" do
      %{conversation: conversation} = conversation_with_message()
      scope = admin_scope()

      before = Repo.aggregate(Participant, :count)

      assert {:ok, _result} = GetMonitoredConversation.execute(scope, conversation.id)

      assert Repo.aggregate(Participant, :count) == before
      refute Messaging.participant?(conversation.id, scope.user.id)
    end

    test "leaves the real participants' last_read_at untouched" do
      conversation = insert(:conversation_schema)
      parent = AccountsFixtures.user_fixture()
      read_at = ~U[2026-01-01 12:00:00Z]

      participant =
        insert(:participant_schema,
          conversation_id: conversation.id,
          user_id: parent.id,
          last_read_at: read_at
        )

      {:ok, _message} =
        Messaging.create_message(%{
          conversation_id: conversation.id,
          sender_id: parent.id,
          content: "Hello"
        })

      assert {:ok, _result} = GetMonitoredConversation.execute(admin_scope(), conversation.id)

      assert Repo.get!(Participant, participant.id).last_read_at == read_at
    end
  end

  describe "the write path gained no admin branch" do
    # Design guard, not a feature test: admin monitoring must be readable-only.
    # If someone ever widens `verify_participant/2` instead of adding a separate
    # read gate, this is what notices.
    test "an admin who is not a participant still cannot send a message" do
      %{conversation: conversation} = conversation_with_message()
      admin = AccountsFixtures.user_fixture(is_admin: true)

      assert {:error, :not_participant} =
               Messaging.send_message(conversation.id, admin.id, "I should not be able to do this")
    end
  end
end
