defmodule KlassHero.Provider.Verification.GetVerificationDocumentPreviewTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.Factory
  alias KlassHero.Shared.Adapters.Driven.Storage.StubStorageAdapter

  setup do
    provider = Factory.insert(:provider_profile_schema)
    %{provider: provider}
  end

  describe "execute/2" do
    test "signs against the store passed in opts, not the caller's", %{provider: provider} do
      doc = Factory.insert(:verification_document_schema, provider_profile_id: provider.id)

      {:ok, other_store} =
        StubStorageAdapter.start_link(name: :"storage_#{System.unique_integer([:positive])}")

      StubStorageAdapter.upload(:private, doc.file_url, "file-content", agent: other_store)

      assert {:ok, %{signed_url: nil}} =
               KlassHero.Provider.get_verification_document_preview(doc.id)

      assert {:ok, %{signed_url: url}} =
               KlassHero.Provider.get_verification_document_preview(doc.id,
                 agent: other_store
               )

      assert url =~ "stub://signed/#{doc.file_url}"
    end
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

    test "detects :video preview type for mp4", %{provider: provider} do
      doc =
        Factory.insert(:verification_document_schema,
          provider_profile_id: provider.id,
          document_type: "video_screening",
          original_filename: "screening.mp4"
        )

      assert {:ok, result} = KlassHero.Provider.get_verification_document_preview(doc.id)
      assert result.preview_type == :video
    end

    test "detects :video preview type for mov", %{provider: provider} do
      doc =
        Factory.insert(:verification_document_schema,
          provider_profile_id: provider.id,
          document_type: "video_screening",
          original_filename: "screening.mov"
        )

      assert {:ok, result} = KlassHero.Provider.get_verification_document_preview(doc.id)
      assert result.preview_type == :video
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
