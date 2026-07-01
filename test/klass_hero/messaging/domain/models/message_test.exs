defmodule KlassHero.Messaging.Domain.Models.MessageTest do
  use ExUnit.Case, async: true

  alias KlassHero.Messaging.Attachment
  alias KlassHero.Messaging.Domain.Models.Message

  describe "new/1" do
    test "creates message with valid attributes" do
      attrs = %{
        id: Ecto.UUID.generate(),
        conversation_id: Ecto.UUID.generate(),
        sender_id: Ecto.UUID.generate(),
        content: "Hello, world!"
      }

      assert {:ok, message} = Message.new(attrs)
      assert message.id == attrs.id
      assert message.conversation_id == attrs.conversation_id
      assert message.sender_id == attrs.sender_id
      assert message.content == "Hello, world!"
      assert message.message_type == :text
      assert message.attachments == []
    end

    test "defaults message_type to :text when not provided" do
      attrs = %{
        id: Ecto.UUID.generate(),
        conversation_id: Ecto.UUID.generate(),
        sender_id: Ecto.UUID.generate(),
        content: "Hello!"
      }

      assert {:ok, message} = Message.new(attrs)
      assert message.message_type == :text
    end

    test "allows system message type" do
      attrs = %{
        id: Ecto.UUID.generate(),
        conversation_id: Ecto.UUID.generate(),
        sender_id: Ecto.UUID.generate(),
        content: "User joined",
        message_type: :system
      }

      assert {:ok, message} = Message.new(attrs)
      assert message.message_type == :system
    end

    test "returns error when id is missing" do
      attrs = %{
        conversation_id: Ecto.UUID.generate(),
        sender_id: Ecto.UUID.generate(),
        content: "Hello!"
      }

      assert {:error, ["Missing required fields"]} = Message.new(attrs)
    end

    test "returns error when content is empty" do
      attrs = %{
        id: Ecto.UUID.generate(),
        conversation_id: Ecto.UUID.generate(),
        sender_id: Ecto.UUID.generate(),
        content: ""
      }

      assert {:error, errors} = Message.new(attrs)
      assert "content cannot be empty" in errors
    end

    test "returns error when content is whitespace only" do
      attrs = %{
        id: Ecto.UUID.generate(),
        conversation_id: Ecto.UUID.generate(),
        sender_id: Ecto.UUID.generate(),
        content: "   "
      }

      assert {:error, errors} = Message.new(attrs)
      assert "content cannot be empty" in errors
    end

    test "returns error when content exceeds 10000 characters" do
      long_content = String.duplicate("a", 10_001)

      attrs = %{
        id: Ecto.UUID.generate(),
        conversation_id: Ecto.UUID.generate(),
        sender_id: Ecto.UUID.generate(),
        content: long_content
      }

      assert {:error, errors} = Message.new(attrs)
      assert "content cannot exceed 10000 characters" in errors
    end

    test "accepts content at exactly 10000 characters" do
      content = String.duplicate("a", 10_000)

      attrs = %{
        id: Ecto.UUID.generate(),
        conversation_id: Ecto.UUID.generate(),
        sender_id: Ecto.UUID.generate(),
        content: content
      }

      assert {:ok, message} = Message.new(attrs)
      assert String.length(message.content) == 10_000
    end

    test "returns error when message_type is invalid" do
      attrs = %{
        id: Ecto.UUID.generate(),
        conversation_id: Ecto.UUID.generate(),
        sender_id: Ecto.UUID.generate(),
        content: "Hello!",
        message_type: :invalid_type
      }

      assert {:error, errors} = Message.new(attrs)
      assert Enum.any?(errors, &String.contains?(&1, "message_type must be one of:"))
    end

    test "allows nil content when attachments are present" do
      attachment = %Attachment{
        id: Ecto.UUID.generate(),
        message_id: Ecto.UUID.generate(),
        file_url: "https://example.com/photo.jpg",
        original_filename: "photo.jpg",
        content_type: "image/jpeg",
        file_size_bytes: 1_000_000
      }

      attrs = %{
        id: Ecto.UUID.generate(),
        conversation_id: Ecto.UUID.generate(),
        sender_id: Ecto.UUID.generate(),
        content: nil,
        attachments: [attachment]
      }

      assert {:ok, message} = Message.new(attrs)
      assert message.content == nil
      assert length(message.attachments) == 1
    end

    test "returns error when both content and attachments are empty" do
      attrs = %{
        id: Ecto.UUID.generate(),
        conversation_id: Ecto.UUID.generate(),
        sender_id: Ecto.UUID.generate(),
        content: nil,
        attachments: []
      }

      assert {:error, errors} = Message.new(attrs)
      assert "message must have content or attachments" in errors
    end

    test "allows content with attachments" do
      attachment = %Attachment{
        id: Ecto.UUID.generate(),
        message_id: Ecto.UUID.generate(),
        file_url: "https://example.com/photo.jpg",
        original_filename: "photo.jpg",
        content_type: "image/jpeg",
        file_size_bytes: 1_000_000
      }

      attrs = %{
        id: Ecto.UUID.generate(),
        conversation_id: Ecto.UUID.generate(),
        sender_id: Ecto.UUID.generate(),
        content: "Check out this photo!",
        attachments: [attachment]
      }

      assert {:ok, message} = Message.new(attrs)
      assert message.content == "Check out this photo!"
      assert length(message.attachments) == 1
    end

    test "rejects more than 5 attachments" do
      attachments =
        for _ <- 1..6 do
          %Attachment{
            id: Ecto.UUID.generate(),
            message_id: Ecto.UUID.generate(),
            file_url: "https://example.com/photo.jpg",
            original_filename: "photo.jpg",
            content_type: "image/jpeg",
            file_size_bytes: 1_000_000
          }
        end

      attrs = %{
        id: Ecto.UUID.generate(),
        conversation_id: Ecto.UUID.generate(),
        sender_id: Ecto.UUID.generate(),
        content: nil,
        attachments: attachments
      }

      assert {:error, errors} = Message.new(attrs)
      assert Enum.any?(errors, &String.contains?(&1, "attachments"))
    end
  end

  describe "text?/1" do
    test "returns true for text message" do
      {:ok, message} = build_message(:text)
      assert Message.text?(message)
    end

    test "returns false for system message" do
      {:ok, message} = build_message(:system)
      refute Message.text?(message)
    end
  end

  describe "system?/1" do
    test "returns true for system message" do
      {:ok, message} = build_message(:system)
      assert Message.system?(message)
    end

    test "returns false for text message" do
      {:ok, message} = build_message(:text)
      refute Message.system?(message)
    end
  end

  describe "deleted?/1" do
    test "returns false when deleted_at is nil" do
      {:ok, message} = build_message(:text)
      refute Message.deleted?(message)
    end

    test "returns true when deleted_at is set" do
      {:ok, message} = build_message(:text)
      message = %{message | deleted_at: DateTime.utc_now()}
      assert Message.deleted?(message)
    end
  end

  describe "delete/2" do
    test "sets deleted_at timestamp" do
      {:ok, message} = build_message(:text)
      now = ~U[2025-01-15 12:00:00Z]

      assert {:ok, deleted} = Message.delete(message, now)
      assert deleted.deleted_at == now
    end

    test "uses current time when timestamp not provided" do
      {:ok, message} = build_message(:text)
      before = DateTime.utc_now()

      {:ok, deleted} = Message.delete(message)

      after_time = DateTime.utc_now()
      assert DateTime.compare(deleted.deleted_at, before) in [:gt, :eq]
      assert DateTime.compare(deleted.deleted_at, after_time) in [:lt, :eq]
    end
  end

  describe "valid_message_types/0" do
    test "returns all valid message types" do
      types = Message.valid_message_types()

      assert :text in types
      assert :system in types
      assert length(types) == 2
    end
  end

  defp build_message(type) do
    Message.new(%{
      id: Ecto.UUID.generate(),
      conversation_id: Ecto.UUID.generate(),
      sender_id: Ecto.UUID.generate(),
      content: "Test message",
      message_type: type
    })
  end
end
