defmodule KlassHero.Provider.Application.Queries.Verification.GetVerificationDocumentPreviewTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.Factory
  alias KlassHero.Shared.Adapters.Driven.Storage.StubStorageAdapter

  setup do
    # The use case calls Storage without opts, hitting the globally configured adapter.
    # Start a named Agent so StubStorageAdapter can track file state for this test.
    start_supervised!({StubStorageAdapter, name: StubStorageAdapter})

    provider = Factory.insert(:provider_profile_schema)
    %{provider: provider}
  end

  describe "execute/1" do
    test "returns document with signed URL when file exists in storage", %{provider: provider} do
      doc =
        Factory.insert(:verification_document_schema,
          provider_profile_id: provider.id,
          original_filename: "photo.jpg"
        )

      # Upload file so StubStorageAdapter knows it exists
      StubStorageAdapter.upload(:private, doc.file_url, "file-content", [])

      assert {:ok, result} = KlassHero.Provider.get_verification_document_preview(doc.id)
      assert result.signed_url != nil
      assert result.document.id == to_string(doc.id)
      assert result.provider_business_name == provider.business_name
    end

    test "returns nil signed_url when file missing from storage", %{provider: provider} do
      doc =
        Factory.insert(:verification_document_schema,
          provider_profile_id: provider.id,
          file_url: "verification-docs/providers/#{provider.id}/missing_file.pdf"
        )

      # Agent is running but file was never uploaded → file_exists? returns false
      assert {:ok, result} = KlassHero.Provider.get_verification_document_preview(doc.id)
      assert result.signed_url == nil
      assert result.document.id == to_string(doc.id)
    end

    test "returns :not_found when document doesn't exist" do
      assert {:error, :not_found} =
               KlassHero.Provider.get_verification_document_preview(Ecto.UUID.generate())
    end

    test "detects :image preview type for jpg", %{provider: provider} do
      doc =
        Factory.insert(:verification_document_schema,
          provider_profile_id: provider.id,
          original_filename: "photo.jpg"
        )

      assert {:ok, result} = KlassHero.Provider.get_verification_document_preview(doc.id)
      assert result.preview_type == :image
    end

    test "detects :image preview type for png", %{provider: provider} do
      doc =
        Factory.insert(:verification_document_schema,
          provider_profile_id: provider.id,
          original_filename: "screenshot.png"
        )

      assert {:ok, result} = KlassHero.Provider.get_verification_document_preview(doc.id)
      assert result.preview_type == :image
    end

    test "detects :pdf preview type", %{provider: provider} do
      doc =
        Factory.insert(:verification_document_schema,
          provider_profile_id: provider.id,
          original_filename: "document.pdf"
        )

      assert {:ok, result} = KlassHero.Provider.get_verification_document_preview(doc.id)
      assert result.preview_type == :pdf
    end

    test "detects :other preview type for unknown extension", %{provider: provider} do
      doc =
        Factory.insert(:verification_document_schema,
          provider_profile_id: provider.id,
          original_filename: "file.docx"
        )

      assert {:ok, result} = KlassHero.Provider.get_verification_document_preview(doc.id)
      assert result.preview_type == :other
    end
  end
end
