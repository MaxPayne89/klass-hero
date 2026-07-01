defmodule KlassHero.Messaging.Application.Queries.GetConversationTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.AccountsFixtures
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.MessageRepository
  alias KlassHero.Messaging.Application.Queries.GetConversation
  alias KlassHero.Messaging.Domain.Models.Conversation

  describe "execute/3" do
    test "returns conversation with messages" do
      conversation = insert(:conversation_schema)
      user = AccountsFixtures.user_fixture()

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      {:ok, _msg} =
        MessageRepository.create(%{
          conversation_id: conversation.id,
          sender_id: user.id,
          content: "Hello!"
        })

      assert {:ok, result} = GetConversation.execute(conversation.id, user.id)

      assert %Conversation{} = result.conversation
      assert result.conversation.id == conversation.id
      assert length(result.messages) == 1
      assert hd(result.messages).content == "Hello!"
      assert is_boolean(result.has_more)
      assert is_map(result.sender_names)
    end

    test "includes sender_names mapping" do
      conversation = insert(:conversation_schema)
      user = AccountsFixtures.user_fixture()

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      {:ok, _msg} =
        MessageRepository.create(%{
          conversation_id: conversation.id,
          sender_id: user.id,
          content: "Hello!"
        })

      assert {:ok, result} = GetConversation.execute(conversation.id, user.id)

      assert Map.has_key?(result.sender_names, user.id)
    end

    test "respects pagination limit" do
      conversation = insert(:conversation_schema)
      user = AccountsFixtures.user_fixture()

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      for i <- 1..5 do
        MessageRepository.create(%{
          conversation_id: conversation.id,
          sender_id: user.id,
          content: "Message #{i}"
        })
      end

      assert {:ok, result} = GetConversation.execute(conversation.id, user.id, limit: 3)

      assert length(result.messages) == 3
      assert result.has_more
    end

    test "marks as read when option is true" do
      conversation = insert(:conversation_schema)
      user = AccountsFixtures.user_fixture()

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id,
        last_read_at: nil
      )

      {:ok, _msg} =
        MessageRepository.create(%{
          conversation_id: conversation.id,
          sender_id: user.id,
          content: "Hello!"
        })

      # Truncate to second since utc_datetime fields don't have microsecond precision
      before = DateTime.utc_now() |> DateTime.truncate(:second)
      {:ok, _result} = GetConversation.execute(conversation.id, user.id, mark_as_read: true)

      {:ok, participant} = KlassHero.Messaging.get_participant(conversation.id, user.id)
      assert participant.last_read_at != nil
      assert DateTime.compare(participant.last_read_at, before) in [:gt, :eq]
    end

    test "does not mark as read when option is false" do
      conversation = insert(:conversation_schema)
      user = AccountsFixtures.user_fixture()

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id,
        last_read_at: nil
      )

      {:ok, _result} = GetConversation.execute(conversation.id, user.id, mark_as_read: false)

      {:ok, participant} = KlassHero.Messaging.get_participant(conversation.id, user.id)
      assert is_nil(participant.last_read_at)
    end

    test "returns not_found when conversation does not exist" do
      user = AccountsFixtures.user_fixture()

      assert {:error, :not_found} = GetConversation.execute(Ecto.UUID.generate(), user.id)
    end

    test "returns not_participant when user is not in conversation" do
      conversation = insert(:conversation_schema)
      user = AccountsFixtures.user_fixture()

      assert {:error, :not_participant} = GetConversation.execute(conversation.id, user.id)
    end

    test "returns not_participant when user has left" do
      conversation = insert(:conversation_schema)
      user = AccountsFixtures.user_fixture()

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id,
        left_at: DateTime.utc_now()
      )

      assert {:error, :not_participant} = GetConversation.execute(conversation.id, user.id)
    end
  end
end
