defmodule KlassHero.Provider.Verification.SubmitVerificationDocumentTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.ProviderFixtures
  alias KlassHero.Shared.Adapters.Driven.Storage.StubStorageAdapter

  defmodule FailingStorageAdapter do
    @behaviour KlassHero.Shared.ForStoringFiles

    def upload(_bucket, _path, _binary, _opts), do: {:error, :upload_failed}
    def signed_url(_, _, _, _), do: {:error, :not_implemented}
    def file_exists?(_, _, _), do: {:ok, false}
    def delete(_, _, _), do: :ok
  end

  setup do
    name = :"stub_storage_#{System.unique_integer([:positive])}"
    {:ok, storage} = StubStorageAdapter.start_link(name: name)
    provider = ProviderFixtures.provider_profile_fixture()
    %{provider: provider, storage: storage}
  end

  describe "execute/1" do
    test "uploads document and creates record", %{provider: provider, storage: storage} do
      params = %{
        provider_profile_id: provider.id,
        document_type: "background_check",
        file_binary: "pdf content here",
        original_filename: "check.pdf",
        content_type: "application/pdf",
        storage_opts: [adapter: StubStorageAdapter, agent: storage]
      }

      assert {:ok, doc} = KlassHero.Provider.submit_verification_document(params)
      assert doc.provider_profile_id == provider.id
      assert doc.document_type == :background_check
      assert doc.status == :pending
      assert doc.file_url =~ "verification-docs/providers/#{provider.id}"
    end

    test "rejects a command-dedicated type submitted via the generic path",
         %{provider: provider, storage: storage} do
      # business_registration must go through submit_business_registration/2, which captures the
      # structured legal facts. The generic path would create a pending doc with none of them, so
      # the domain rejects it before any storage upload — the invariant is no longer UI-only.
      params = %{
        provider_profile_id: provider.id,
        document_type: "business_registration",
        file_binary: "pdf content here",
        original_filename: "registration.pdf",
        content_type: "application/pdf",
        storage_opts: [adapter: StubStorageAdapter, agent: storage]
      }

      assert {:error, :dedicated_submission_required} =
               KlassHero.Provider.submit_verification_document(params)

      assert {:ok, []} = KlassHero.Provider.get_provider_verification_documents(provider.id)
    end

    test "stores file content in storage", %{provider: provider, storage: storage} do
      file_content = "test pdf binary content"

      params = %{
        provider_profile_id: provider.id,
        document_type: "insurance_certificate",
        expiry_date: ~D[2027-01-01],
        file_binary: file_content,
        original_filename: "insurance.pdf",
        content_type: "application/pdf",
        storage_opts: [adapter: StubStorageAdapter, agent: storage]
      }

      assert {:ok, doc} = KlassHero.Provider.submit_verification_document(params)

      # Verify file was stored in the stub adapter
      assert {:ok, ^file_content} =
               StubStorageAdapter.get_uploaded(:private, doc.file_url, agent: storage)
    end

    test "sanitizes filename to remove unsafe characters", %{provider: provider, storage: storage} do
      params = %{
        provider_profile_id: provider.id,
        document_type: "id_document",
        file_binary: "content",
        original_filename: "my file (1).pdf",
        content_type: "application/pdf",
        storage_opts: [adapter: StubStorageAdapter, agent: storage]
      }

      assert {:ok, doc} = KlassHero.Provider.submit_verification_document(params)
      # Parentheses and spaces should be replaced with underscores
      assert doc.file_url =~ "my_file__1_.pdf"
    end

    test "rejects invalid document type", %{provider: provider, storage: storage} do
      params = %{
        provider_profile_id: provider.id,
        document_type: "invalid_type",
        file_binary: "content",
        original_filename: "doc.pdf",
        content_type: "application/pdf",
        storage_opts: [adapter: StubStorageAdapter, agent: storage]
      }

      assert {:error, %Ecto.Changeset{} = changeset} =
               KlassHero.Provider.submit_verification_document(params)

      assert :document_type in Keyword.keys(changeset.errors)
    end

    test "accepts all generic-submittable document types", %{provider: provider, storage: storage} do
      # business_registration is command-dedicated — it has its own path and is rejected here
      # (covered by the dedicated-command test above), so it is absent from this list.
      valid_types =
        ~w(insurance_certificate id_document tax_certificate other
           experience_validation background_check video_screening safeguarding_certificate)

      for doc_type <- valid_types do
        params = %{
          provider_profile_id: provider.id,
          document_type: doc_type,
          # Harmless for non-expiring types (optional); satisfies insurance's required expiry.
          expiry_date: ~D[2027-01-01],
          file_binary: "content for #{doc_type}",
          original_filename: "#{doc_type}.pdf",
          content_type: "application/pdf",
          storage_opts: [adapter: StubStorageAdapter, agent: storage]
        }

        assert {:ok, doc} = KlassHero.Provider.submit_verification_document(params)
        assert doc.document_type == String.to_existing_atom(doc_type)
      end
    end

    test "requires provider_profile_id", %{storage: storage} do
      params = %{
        document_type: "background_check",
        file_binary: "content",
        original_filename: "doc.pdf",
        content_type: "application/pdf",
        storage_opts: [adapter: StubStorageAdapter, agent: storage]
      }

      assert {:error, errors} = KlassHero.Provider.submit_verification_document(params)
      assert :provider_profile_id in Keyword.keys(errors)
    end

    test "requires file_binary", %{provider: provider, storage: storage} do
      params = %{
        provider_profile_id: provider.id,
        document_type: "background_check",
        original_filename: "doc.pdf",
        content_type: "application/pdf",
        storage_opts: [adapter: StubStorageAdapter, agent: storage]
      }

      assert {:error, errors} = KlassHero.Provider.submit_verification_document(params)
      assert :file_binary in Keyword.keys(errors)
    end

    test "requires original_filename", %{provider: provider, storage: storage} do
      params = %{
        provider_profile_id: provider.id,
        document_type: "background_check",
        file_binary: "content",
        content_type: "application/pdf",
        storage_opts: [adapter: StubStorageAdapter, agent: storage]
      }

      assert {:error, errors} = KlassHero.Provider.submit_verification_document(params)
      assert :original_filename in Keyword.keys(errors)
    end

    test "returns error when storage upload fails", %{provider: provider} do
      params = %{
        provider_profile_id: provider.id,
        document_type: "background_check",
        file_binary: "content",
        original_filename: "doc.pdf",
        storage_opts: [adapter: FailingStorageAdapter]
      }

      # Trigger: storage adapter returns {:error, :upload_failed}
      # Why: the with chain should propagate the storage error
      # Outcome: no document record created, error returned to caller
      assert {:error, :upload_failed} = KlassHero.Provider.submit_verification_document(params)

      # Verify no document was persisted
      assert {:ok, []} = KlassHero.Provider.get_provider_verification_documents(provider.id)
    end
  end

  describe "expiry_date (B3, #957)" do
    test "persists expiry_date for an insurance certificate", %{provider: provider, storage: storage} do
      params = %{
        provider_profile_id: provider.id,
        document_type: "insurance_certificate",
        expiry_date: ~D[2027-03-15],
        file_binary: "content",
        original_filename: "insurance.pdf",
        content_type: "application/pdf",
        storage_opts: [adapter: StubStorageAdapter, agent: storage]
      }

      assert {:ok, doc} = KlassHero.Provider.submit_verification_document(params)
      assert doc.expiry_date == ~D[2027-03-15]
    end

    test "requires expiry_date for an insurance certificate", %{provider: provider, storage: storage} do
      params = %{
        provider_profile_id: provider.id,
        document_type: "insurance_certificate",
        file_binary: "content",
        original_filename: "insurance.pdf",
        content_type: "application/pdf",
        storage_opts: [adapter: StubStorageAdapter, agent: storage]
      }

      assert {:error, errors} = KlassHero.Provider.submit_verification_document(params)
      assert :expiry_date in Keyword.keys(errors)

      # And nothing was persisted — the missing date is caught before the storage upload.
      assert {:ok, []} = KlassHero.Provider.get_provider_verification_documents(provider.id)
    end

    test "does not require expiry_date for non-expiring types", %{provider: provider, storage: storage} do
      params = %{
        provider_profile_id: provider.id,
        document_type: "background_check",
        file_binary: "content",
        original_filename: "bg.pdf",
        content_type: "application/pdf",
        storage_opts: [adapter: StubStorageAdapter, agent: storage]
      }

      assert {:ok, doc} = KlassHero.Provider.submit_verification_document(params)
      assert doc.expiry_date == nil
    end
  end
end
