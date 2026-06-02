defmodule KlassHero.Messaging.Adapters.Driven.Persistence.Mappers.AttachmentMapperTest do
  use ExUnit.Case, async: true

  alias KlassHero.Messaging.Adapters.Driven.Persistence.Mappers.AttachmentMapper
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.AttachmentSchema
  alias KlassHero.Messaging.Domain.Models.Attachment

  describe "to_domain/1" do
    test "maps all fields from schema to domain struct" do
      id = Ecto.UUID.generate()
      message_id = Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      schema = %AttachmentSchema{
        id: id,
        message_id: message_id,
        file_url: "https://cdn.example.com/uploads/photo.jpg",
        original_filename: "photo.jpg",
        content_type: "image/jpeg",
        file_size_bytes: 204_800,
        inserted_at: now,
        updated_at: now
      }

      result = AttachmentMapper.to_domain(schema)

      assert %Attachment{} = result
      assert result.id == id
      assert result.message_id == message_id
      assert result.file_url == "https://cdn.example.com/uploads/photo.jpg"
      assert result.original_filename == "photo.jpg"
      assert result.content_type == "image/jpeg"
      assert result.file_size_bytes == 204_800
      assert result.inserted_at == now
      assert result.updated_at == now
    end

    test "maps nil timestamps" do
      schema = build_schema(inserted_at: nil, updated_at: nil)

      result = AttachmentMapper.to_domain(schema)

      assert result.inserted_at == nil
      assert result.updated_at == nil
    end

    test "preserves content_type without transformation" do
      for content_type <- ~w(image/jpeg image/png image/gif image/webp) do
        schema = build_schema(content_type: content_type)
        result = AttachmentMapper.to_domain(schema)
        assert result.content_type == content_type
      end
    end

    test "preserves large file_size_bytes" do
      schema = build_schema(file_size_bytes: 10_485_760)

      result = AttachmentMapper.to_domain(schema)

      assert result.file_size_bytes == 10_485_760
    end
  end

  describe "to_create_attrs/1" do
    test "selects only the expected persistence fields" do
      attrs = %{
        message_id: Ecto.UUID.generate(),
        file_url: "https://cdn.example.com/file.png",
        storage_path: "uploads/2025/file.png",
        original_filename: "file.png",
        content_type: "image/png",
        file_size_bytes: 51_200
      }

      result = AttachmentMapper.to_create_attrs(attrs)

      assert result == attrs
    end

    test "filters out extraneous keys not needed for persistence" do
      attrs = %{
        message_id: Ecto.UUID.generate(),
        file_url: "https://cdn.example.com/img.jpg",
        storage_path: "uploads/img.jpg",
        original_filename: "img.jpg",
        content_type: "image/jpeg",
        file_size_bytes: 10_000,
        extra_key: "should be removed",
        another_extra: 42
      }

      result = AttachmentMapper.to_create_attrs(attrs)

      refute Map.has_key?(result, :extra_key)
      refute Map.has_key?(result, :another_extra)
    end

    test "includes storage_path (not present in domain model)" do
      storage_path = "uploads/2025/04/abc123.jpg"
      attrs = %{
        message_id: Ecto.UUID.generate(),
        file_url: "https://cdn.example.com/abc123.jpg",
        storage_path: storage_path,
        original_filename: "abc123.jpg",
        content_type: "image/jpeg",
        file_size_bytes: 8_192
      }

      result = AttachmentMapper.to_create_attrs(attrs)

      assert result.storage_path == storage_path
    end

    test "handles partial attrs map - returns only matching keys" do
      attrs = %{message_id: Ecto.UUID.generate(), file_url: "https://cdn.example.com/x.jpg"}

      result = AttachmentMapper.to_create_attrs(attrs)

      assert Map.has_key?(result, :message_id)
      assert Map.has_key?(result, :file_url)
      refute Map.has_key?(result, :storage_path)
      refute Map.has_key?(result, :original_filename)
    end
  end

  defp build_schema(overrides) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    defaults = %{
      id: Ecto.UUID.generate(),
      message_id: Ecto.UUID.generate(),
      file_url: "https://cdn.example.com/default.jpg",
      original_filename: "default.jpg",
      content_type: "image/jpeg",
      file_size_bytes: 102_400,
      inserted_at: now,
      updated_at: now
    }

    struct!(AttachmentSchema, Map.merge(defaults, Map.new(overrides)))
  end
end
