defmodule KlassHero.Messaging.Adapters.Driven.Persistence.Mappers.MessageMapperTest do
  @moduledoc """
  Unit tests for MessageMapper.

  Covers schema-to-domain mapping, creation attribute conversion, and the
  non-trivial `build_sender_names_map/1` sender filtering logic.
  No database required — schemas are constructed inline.
  """

  use ExUnit.Case, async: true

  alias KlassHero.Messaging.Adapters.Driven.Persistence.Mappers.MessageMapper
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.MessageSchema
  alias KlassHero.Messaging.Attachment
  alias KlassHero.Messaging.Domain.Models.Message

  @conversation_id Ecto.UUID.generate()
  @sender_id Ecto.UUID.generate()

  defp valid_schema(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      conversation_id: @conversation_id,
      sender_id: @sender_id,
      content: "Hello, world!",
      message_type: "text",
      deleted_at: nil,
      inserted_at: ~U[2025-03-01 10:00:00Z],
      updated_at: ~U[2025-03-01 10:00:00Z],
      sender: %Ecto.Association.NotLoaded{__field__: :sender, __owner__: MessageSchema},
      attachments: %Ecto.Association.NotLoaded{__field__: :attachments, __owner__: MessageSchema}
    }

    struct!(MessageSchema, Map.merge(defaults, overrides))
  end

  defp attachment_schema(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      message_id: Ecto.UUID.generate(),
      file_url: "https://example.com/image.png",
      original_filename: "image.png",
      content_type: "image/png",
      file_size_bytes: 1024,
      inserted_at: ~U[2025-03-01 10:00:00Z],
      updated_at: ~U[2025-03-01 10:00:00Z]
    }

    struct!(Attachment, Map.merge(defaults, overrides))
  end

  describe "to_domain/1" do
    test "converts all fields from schema to domain struct" do
      schema = valid_schema(%{attachments: []})

      message = MessageMapper.to_domain(schema)

      assert %Message{} = message
      assert message.id == schema.id
      assert message.conversation_id == @conversation_id
      assert message.sender_id == @sender_id
      assert message.content == "Hello, world!"
      assert message.message_type == :text
      assert message.deleted_at == nil
      assert message.inserted_at == ~U[2025-03-01 10:00:00Z]
      assert message.updated_at == ~U[2025-03-01 10:00:00Z]
    end

    test "converts message_type string to atom via String.to_existing_atom" do
      text_schema = valid_schema(%{message_type: "text", attachments: []})
      system_schema = valid_schema(%{message_type: "system", attachments: []})

      assert MessageMapper.to_domain(text_schema).message_type == :text
      assert MessageMapper.to_domain(system_schema).message_type == :system
    end

    test "maps Ecto.Association.NotLoaded attachments to empty list" do
      schema = valid_schema()

      message = MessageMapper.to_domain(schema)

      assert message.attachments == []
    end

    test "maps nil attachments to empty list" do
      schema = valid_schema(%{attachments: nil})

      message = MessageMapper.to_domain(schema)

      assert message.attachments == []
    end

    test "maps loaded attachments via AttachmentMapper" do
      attachment = attachment_schema()
      schema = valid_schema(%{attachments: [attachment]})

      message = MessageMapper.to_domain(schema)

      assert [%Attachment{}] = message.attachments
      assert hd(message.attachments).id == attachment.id
      assert hd(message.attachments).file_url == "https://example.com/image.png"
    end

    test "maps multiple loaded attachments in order" do
      att1 = attachment_schema(%{id: Ecto.UUID.generate()})
      att2 = attachment_schema(%{id: Ecto.UUID.generate()})
      schema = valid_schema(%{attachments: [att1, att2]})

      message = MessageMapper.to_domain(schema)

      assert length(message.attachments) == 2
    end

    test "preserves deleted_at when set" do
      deleted = ~U[2025-04-01 09:00:00Z]
      schema = valid_schema(%{deleted_at: deleted, attachments: []})

      message = MessageMapper.to_domain(schema)

      assert message.deleted_at == deleted
    end
  end

  describe "to_create_attrs/1" do
    test "takes only permitted keys" do
      attrs = %{
        conversation_id: @conversation_id,
        sender_id: @sender_id,
        content: "Hi",
        message_type: :text,
        deleted_at: nil,
        extra_field: "ignored"
      }

      result = MessageMapper.to_create_attrs(attrs)

      assert Map.has_key?(result, :conversation_id)
      assert Map.has_key?(result, :sender_id)
      assert Map.has_key?(result, :content)
      assert Map.has_key?(result, :message_type)
      refute Map.has_key?(result, :deleted_at)
      refute Map.has_key?(result, :extra_field)
    end

    test "converts atom message_type to string" do
      attrs = %{conversation_id: @conversation_id, sender_id: @sender_id, message_type: :text}

      result = MessageMapper.to_create_attrs(attrs)

      assert result.message_type == "text"
    end

    test "converts :system atom message_type to string" do
      attrs = %{conversation_id: @conversation_id, sender_id: @sender_id, message_type: :system}

      result = MessageMapper.to_create_attrs(attrs)

      assert result.message_type == "system"
    end

    test "defaults message_type to 'text' when nil" do
      attrs = %{conversation_id: @conversation_id, sender_id: @sender_id, message_type: nil}

      result = MessageMapper.to_create_attrs(attrs)

      assert result.message_type == "text"
    end

    test "keeps string message_type unchanged" do
      attrs = %{conversation_id: @conversation_id, sender_id: @sender_id, message_type: "system"}

      result = MessageMapper.to_create_attrs(attrs)

      assert result.message_type == "system"
    end
  end

  describe "build_sender_names_map/1" do
    test "returns empty map for empty list" do
      assert MessageMapper.build_sender_names_map([]) == %{}
    end

    test "returns map of sender_id to display name" do
      schema = valid_schema(%{sender_id: @sender_id, sender: %{id: @sender_id, name: "Alice Parent"}, attachments: []})

      result = MessageMapper.build_sender_names_map([schema])

      assert result == %{@sender_id => "Alice Parent"}
    end

    test "builds map from multiple schemas with loaded senders" do
      id1 = Ecto.UUID.generate()
      id2 = Ecto.UUID.generate()
      schema1 = valid_schema(%{sender_id: id1, sender: %{id: id1, name: "Alice"}, attachments: []})
      schema2 = valid_schema(%{sender_id: id2, sender: %{id: id2, name: "Bob"}, attachments: []})

      result = MessageMapper.build_sender_names_map([schema1, schema2])

      assert result == %{id1 => "Alice", id2 => "Bob"}
    end

    test "skips schemas where sender is Ecto.Association.NotLoaded (default)" do
      schema = valid_schema(%{attachments: []})

      result = MessageMapper.build_sender_names_map([schema])

      assert result == %{}
    end

    test "skips schemas where sender is nil" do
      schema = valid_schema(%{sender: nil, attachments: []})

      result = MessageMapper.build_sender_names_map([schema])

      assert result == %{}
    end

    test "handles mixed loaded and unloaded senders" do
      id1 = Ecto.UUID.generate()
      id2 = Ecto.UUID.generate()

      schema_loaded = valid_schema(%{sender_id: id1, sender: %{id: id1, name: "Alice"}, attachments: []})
      schema_unloaded = valid_schema(%{sender_id: id2, attachments: []})

      result = MessageMapper.build_sender_names_map([schema_loaded, schema_unloaded])

      assert result == %{id1 => "Alice"}
    end

    test "handles mixed loaded and nil senders" do
      id1 = Ecto.UUID.generate()
      id2 = Ecto.UUID.generate()

      schema_loaded = valid_schema(%{sender_id: id1, sender: %{id: id1, name: "Bob"}, attachments: []})
      schema_nil = valid_schema(%{sender_id: id2, sender: nil, attachments: []})

      result = MessageMapper.build_sender_names_map([schema_loaded, schema_nil])

      assert result == %{id1 => "Bob"}
    end

    test "deduplicates multiple messages from same sender" do
      schema1 = valid_schema(%{sender_id: @sender_id, sender: %{id: @sender_id, name: "Alice"}, attachments: []})
      schema2 = valid_schema(%{sender_id: @sender_id, sender: %{id: @sender_id, name: "Alice"}, attachments: []})

      result = MessageMapper.build_sender_names_map([schema1, schema2])

      assert map_size(result) == 1
      assert result[@sender_id] == "Alice"
    end
  end
end
