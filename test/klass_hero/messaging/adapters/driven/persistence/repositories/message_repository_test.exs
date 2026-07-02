defmodule KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.MessageRepositoryTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.AccountsFixtures
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.MessageRepository
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.MessageSchema
  alias KlassHero.Messaging.Conversation
  alias KlassHero.Messaging.Domain.Models.Message

  describe "create/1" do
    test "creates message with valid attributes" do
      conversation = insert(:conversation_schema)
      user = AccountsFixtures.user_fixture()

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      attrs = %{
        conversation_id: conversation.id,
        sender_id: user.id,
        content: "Hello, world!",
        message_type: :text
      }

      assert {:ok, message} = MessageRepository.create(attrs)
      assert %Message{} = message
      assert message.conversation_id == conversation.id
      assert message.sender_id == user.id
      assert message.content == "Hello, world!"
      assert message.message_type == :text
    end

    test "defaults message_type to text" do
      conversation = insert(:conversation_schema)
      user = AccountsFixtures.user_fixture()

      attrs = %{
        conversation_id: conversation.id,
        sender_id: user.id,
        content: "Hello!"
      }

      assert {:ok, message} = MessageRepository.create(attrs)
      assert message.message_type == :text
    end

    test "returns error for invalid conversation_id" do
      user = AccountsFixtures.user_fixture()

      attrs = %{
        conversation_id: Ecto.UUID.generate(),
        sender_id: user.id,
        content: "Hello!"
      }

      assert {:error, changeset} = MessageRepository.create(attrs)
      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "get_by_id/1" do
    test "returns message when found" do
      message_schema = insert(:message_schema)

      assert {:ok, message} = MessageRepository.get_by_id(message_schema.id)
      assert %Message{} = message
      assert message.id == message_schema.id
    end

    test "returns not_found when message does not exist" do
      assert {:error, :not_found} = MessageRepository.get_by_id(Ecto.UUID.generate())
    end
  end

  describe "list_for_conversation/2" do
    test "returns messages for conversation ordered by newest first" do
      conversation = insert(:conversation_schema)
      user = AccountsFixtures.user_fixture()

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      {:ok, msg1} =
        MessageRepository.create(%{
          conversation_id: conversation.id,
          sender_id: user.id,
          content: "First message"
        })

      # Sleep for 1 second to ensure different timestamps (utc_datetime has second precision)
      Process.sleep(1100)

      {:ok, msg2} =
        MessageRepository.create(%{
          conversation_id: conversation.id,
          sender_id: user.id,
          content: "Second message"
        })

      assert {:ok, messages, _has_more} =
               MessageRepository.list_for_conversation(conversation.id)

      assert length(messages) == 2
      assert hd(messages).id == msg2.id
      assert List.last(messages).id == msg1.id
    end

    test "excludes deleted messages" do
      conversation = insert(:conversation_schema)
      user = AccountsFixtures.user_fixture()

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      {:ok, msg1} =
        MessageRepository.create(%{
          conversation_id: conversation.id,
          sender_id: user.id,
          content: "Visible message"
        })

      {:ok, msg2} =
        MessageRepository.create(%{
          conversation_id: conversation.id,
          sender_id: user.id,
          content: "Deleted message"
        })

      {:ok, _deleted} = MessageRepository.soft_delete(msg2)

      assert {:ok, messages, _has_more} =
               MessageRepository.list_for_conversation(conversation.id)

      assert length(messages) == 1
      assert hd(messages).id == msg1.id
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

      assert {:ok, messages, has_more} =
               MessageRepository.list_for_conversation(conversation.id, limit: 3)

      assert length(messages) == 3
      assert has_more
    end
  end

  describe "get_latest/1" do
    test "returns the most recent message" do
      alias KlassHero.Repo

      conversation = insert(:conversation_schema)
      user = AccountsFixtures.user_fixture()

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      {:ok, first_msg} =
        MessageRepository.create(%{
          conversation_id: conversation.id,
          sender_id: user.id,
          content: "First message"
        })

      # Update first message's timestamp to be 2 seconds earlier to ensure proper ordering
      earlier_time =
        DateTime.utc_now()
        |> DateTime.add(-2, :second)
        |> DateTime.truncate(:second)

      Repo.get(MessageSchema, first_msg.id)
      |> Ecto.Changeset.change(inserted_at: earlier_time)
      |> Repo.update!()

      {:ok, latest_msg} =
        MessageRepository.create(%{
          conversation_id: conversation.id,
          sender_id: user.id,
          content: "Latest message"
        })

      assert {:ok, message} = MessageRepository.get_latest(conversation.id)
      assert message.id == latest_msg.id
      assert message.content == "Latest message"
    end

    test "excludes deleted messages from latest" do
      conversation = insert(:conversation_schema)
      user = AccountsFixtures.user_fixture()

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      {:ok, first_msg} =
        MessageRepository.create(%{
          conversation_id: conversation.id,
          sender_id: user.id,
          content: "First message"
        })

      Process.sleep(10)

      {:ok, deleted_msg} =
        MessageRepository.create(%{
          conversation_id: conversation.id,
          sender_id: user.id,
          content: "Deleted message"
        })

      {:ok, _} = MessageRepository.soft_delete(deleted_msg)

      assert {:ok, message} = MessageRepository.get_latest(conversation.id)
      assert message.id == first_msg.id
    end

    test "returns not_found when no messages exist" do
      conversation = insert(:conversation_schema)

      assert {:error, :not_found} = MessageRepository.get_latest(conversation.id)
    end
  end

  describe "soft_delete/1" do
    test "sets deleted_at timestamp" do
      message_schema = insert(:message_schema)
      {:ok, message} = MessageRepository.get_by_id(message_schema.id)

      assert {:ok, deleted} = MessageRepository.soft_delete(message)
      assert deleted.deleted_at != nil
    end

    test "returns not_found for non-existent message" do
      fake_message = %Message{
        id: Ecto.UUID.generate(),
        conversation_id: Ecto.UUID.generate(),
        sender_id: Ecto.UUID.generate(),
        content: "Test"
      }

      assert {:error, :not_found} = MessageRepository.soft_delete(fake_message)
    end
  end

  describe "count_unread/2" do
    test "counts messages after last_read_at" do
      conversation = insert(:conversation_schema)
      user = AccountsFixtures.user_fixture()

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      read_at = ~U[2025-01-15 12:00:00Z]

      MessageRepository.create(%{
        conversation_id: conversation.id,
        sender_id: user.id,
        content: "Before read"
      })

      Process.sleep(10)

      MessageRepository.create(%{
        conversation_id: conversation.id,
        sender_id: user.id,
        content: "After read"
      })

      count = MessageRepository.count_unread(conversation.id, read_at)
      assert count >= 1
    end

    test "counts all messages when last_read_at is nil" do
      conversation = insert(:conversation_schema)
      user = AccountsFixtures.user_fixture()

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      MessageRepository.create(%{
        conversation_id: conversation.id,
        sender_id: user.id,
        content: "Message 1"
      })

      MessageRepository.create(%{
        conversation_id: conversation.id,
        sender_id: user.id,
        content: "Message 2"
      })

      count = MessageRepository.count_unread(conversation.id, nil)
      assert count == 2
    end

    test "returns 0 when no messages exist" do
      conversation = insert(:conversation_schema)

      count = MessageRepository.count_unread(conversation.id, nil)
      assert count == 0
    end
  end

  describe "anonymize_for_sender/1" do
    test "replaces content with [deleted] for all messages by sender and returns count" do
      conversation = insert(:conversation_schema)
      user = AccountsFixtures.user_fixture()

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      MessageRepository.create(%{
        conversation_id: conversation.id,
        sender_id: user.id,
        content: "Message 1"
      })

      MessageRepository.create(%{
        conversation_id: conversation.id,
        sender_id: user.id,
        content: "Message 2"
      })

      assert {:ok, 2} = MessageRepository.anonymize_for_sender(user.id)

      # Verify content replaced
      messages = Repo.all(from(m in MessageSchema, where: m.sender_id == ^user.id))
      assert Enum.all?(messages, &(&1.content == "[deleted]"))
    end

    test "does not affect messages from other senders" do
      conversation = insert(:conversation_schema)
      user = AccountsFixtures.user_fixture()
      other_user = AccountsFixtures.user_fixture()

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: other_user.id
      )

      MessageRepository.create(%{
        conversation_id: conversation.id,
        sender_id: user.id,
        content: "User message"
      })

      MessageRepository.create(%{
        conversation_id: conversation.id,
        sender_id: other_user.id,
        content: "Other user message"
      })

      assert {:ok, 1} = MessageRepository.anonymize_for_sender(user.id)

      # Verify other user's message untouched
      other_messages =
        Repo.all(from(m in MessageSchema, where: m.sender_id == ^other_user.id))

      assert Enum.all?(other_messages, &(&1.content == "Other user message"))
    end

    test "returns zero count when user has no messages" do
      user = AccountsFixtures.user_fixture()

      assert {:ok, 0} = MessageRepository.anonymize_for_sender(user.id)
    end
  end

  describe "delete_for_expired_conversations/1" do
    test "deletes messages for expired conversations" do
      alias KlassHero.Repo

      conversation = insert(:conversation_schema)
      user = AccountsFixtures.user_fixture()

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      # Set retention_until in the past to make it expired
      past_retention =
        DateTime.utc_now() |> DateTime.add(-5, :day) |> DateTime.truncate(:second)

      Repo.get(Conversation, conversation.id)
      |> Ecto.Changeset.change(
        archived_at: DateTime.utc_now() |> DateTime.add(-35, :day) |> DateTime.truncate(:second),
        retention_until: past_retention
      )
      |> Repo.update!()

      {:ok, msg1} =
        MessageRepository.create(%{
          conversation_id: conversation.id,
          sender_id: user.id,
          content: "Message 1"
        })

      {:ok, msg2} =
        MessageRepository.create(%{
          conversation_id: conversation.id,
          sender_id: user.id,
          content: "Message 2"
        })

      now = DateTime.utc_now()

      assert {:ok, count, conv_ids} = MessageRepository.delete_for_expired_conversations(now)

      assert count == 2
      assert conversation.id in conv_ids

      # Verify messages are deleted
      assert {:error, :not_found} = MessageRepository.get_by_id(msg1.id)
      assert {:error, :not_found} = MessageRepository.get_by_id(msg2.id)
    end

    test "returns empty result when no expired conversations" do
      conversation = insert(:conversation_schema)
      user = AccountsFixtures.user_fixture()

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      {:ok, message} =
        MessageRepository.create(%{
          conversation_id: conversation.id,
          sender_id: user.id,
          content: "Active message"
        })

      now = DateTime.utc_now()

      assert {:ok, 0, []} = MessageRepository.delete_for_expired_conversations(now)

      # Verify message still exists
      assert {:ok, _} = MessageRepository.get_by_id(message.id)
    end

    test "does not delete messages for conversations with future retention" do
      alias KlassHero.Repo

      conversation = insert(:conversation_schema)
      user = AccountsFixtures.user_fixture()

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      # Set retention_until in the future
      future_retention =
        DateTime.utc_now() |> DateTime.add(20, :day) |> DateTime.truncate(:second)

      Repo.get(Conversation, conversation.id)
      |> Ecto.Changeset.change(
        archived_at: DateTime.utc_now() |> DateTime.add(-10, :day) |> DateTime.truncate(:second),
        retention_until: future_retention
      )
      |> Repo.update!()

      {:ok, message} =
        MessageRepository.create(%{
          conversation_id: conversation.id,
          sender_id: user.id,
          content: "Message with future retention"
        })

      now = DateTime.utc_now()

      assert {:ok, 0, []} = MessageRepository.delete_for_expired_conversations(now)

      # Verify message still exists
      assert {:ok, _} = MessageRepository.get_by_id(message.id)
    end
  end
end
