defmodule KlassHero.Messaging.AttachmentTest do
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias KlassHero.Messaging.Attachment

  describe "create_changeset/2" do
    test "is valid with all required attributes" do
      changeset = Attachment.create_changeset(%Attachment{}, valid_attrs())
      assert changeset.valid?
    end

    test "accepts all allowed image content types" do
      for content_type <- ~w(image/jpeg image/png image/gif image/webp) do
        changeset = Attachment.create_changeset(%Attachment{}, valid_attrs(%{content_type: content_type}))
        assert changeset.valid?, "expected #{content_type} to be valid"
      end
    end

    test "rejects unsupported content type" do
      changeset = Attachment.create_changeset(%Attachment{}, valid_attrs(%{content_type: "application/pdf"}))
      assert %{content_type: [msg]} = errors_on(changeset)
      assert msg =~ "must be one of"
    end

    test "rejects file exceeding 10 MB" do
      changeset = Attachment.create_changeset(%Attachment{}, valid_attrs(%{file_size_bytes: 10_485_761}))
      assert %{file_size_bytes: [msg]} = errors_on(changeset)
      assert msg =~ "must be between"
    end

    test "accepts file at exactly 10 MB" do
      changeset = Attachment.create_changeset(%Attachment{}, valid_attrs(%{file_size_bytes: 10_485_760}))
      assert changeset.valid?
    end

    test "rejects zero file size" do
      changeset = Attachment.create_changeset(%Attachment{}, valid_attrs(%{file_size_bytes: 0}))
      assert %{file_size_bytes: [_]} = errors_on(changeset)
    end

    test "requires all fields including message_id and storage_path" do
      changeset = Attachment.create_changeset(%Attachment{}, %{})

      errors = errors_on(changeset)
      assert errors.message_id == ["can't be blank"]
      assert errors.file_url == ["can't be blank"]
      assert errors.storage_path == ["can't be blank"]
      assert errors.original_filename == ["can't be blank"]
      assert errors.content_type == ["can't be blank"]
      assert errors.file_size_bytes == ["can't be blank"]
    end
  end

  describe "constants" do
    test "allowed_content_types/0 returns the image MIME types" do
      types = Attachment.allowed_content_types()
      assert "image/jpeg" in types
      assert "image/png" in types
      assert "image/gif" in types
      assert "image/webp" in types
    end

    test "max_file_size_bytes/0 is 10 MB" do
      assert Attachment.max_file_size_bytes() == 10_485_760
    end

    test "max_per_message/0 is 5" do
      assert Attachment.max_per_message() == 5
    end
  end

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        message_id: Ecto.UUID.generate(),
        file_url: "https://s3.example.com/messaging/attachments/#{Ecto.UUID.generate()}/photo.jpg",
        storage_path: "messaging/attachments/#{Ecto.UUID.generate()}/photo.jpg",
        original_filename: "photo.jpg",
        content_type: "image/jpeg",
        file_size_bytes: 2_400_000
      },
      overrides
    )
  end

  defp errors_on(changeset) do
    Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
