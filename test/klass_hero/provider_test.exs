defmodule KlassHero.ProviderTest do
  @moduledoc """
  Integration tests for the Provider context public API.

  Tests the complete flow from context facade through use cases to repositories.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.EventTestHelper

  alias KlassHero.AccountsFixtures
  alias KlassHero.Provider
  alias KlassHero.Provider.ProviderProfile
  alias KlassHero.Provider.VerificationDocument
  alias KlassHero.ProviderFixtures
  alias KlassHero.Shared.Adapters.Driven.Storage.StubStorageAdapter

  # Provider Profile Functions

  describe "create_provider_profile/1" do
    test "creates provider profile through public API" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])

      attrs = %{
        identity_id: user.id,
        business_name: "Kids Sports Academy"
      }

      assert {:ok, %ProviderProfile{} = profile} = Provider.create_provider_profile(attrs)
      assert profile.identity_id == attrs.identity_id
      assert profile.business_name == "Kids Sports Academy"
    end

    test "returns validation error for invalid attrs" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])
      attrs = %{identity_id: user.id, business_name: ""}

      assert {:error, {:validation_error, errors}} = Provider.create_provider_profile(attrs)
      assert "Business name cannot be empty" in errors
    end

    test "returns duplicate error when profile exists" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])
      attrs = %{identity_id: user.id, business_name: "My Business"}

      assert {:ok, _} = Provider.create_provider_profile(attrs)
      assert {:error, :duplicate_resource} = Provider.create_provider_profile(attrs)
    end
  end

  describe "get_provider_by_identity/1" do
    test "retrieves existing provider profile" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])

      {:ok, created} =
        Provider.create_provider_profile(%{
          identity_id: user.id,
          business_name: "My Business"
        })

      assert {:ok, %ProviderProfile{} = retrieved} =
               Provider.get_provider_by_identity(user.id)

      assert retrieved.id == created.id
    end

    test "returns not_found for non-existent profile" do
      assert {:error, :not_found} = Provider.get_provider_by_identity(Ecto.UUID.generate())
    end
  end

  describe "has_provider_profile?/1" do
    test "returns true when profile exists" do
      user = AccountsFixtures.unconfirmed_user_fixture(intended_roles: [:provider])

      {:ok, _} =
        Provider.create_provider_profile(%{
          identity_id: user.id,
          business_name: "My Business"
        })

      assert Provider.has_provider_profile?(user.id) == true
    end

    test "returns false when profile does not exist" do
      assert Provider.has_provider_profile?(Ecto.UUID.generate()) == false
    end
  end

  # Verification Document Functions

  describe "submit_verification_document/1" do
    setup do
      name = :"stub_storage_#{System.unique_integer([:positive])}"
      {:ok, storage} = StubStorageAdapter.start_link(name: name)
      provider = ProviderFixtures.provider_profile_fixture()
      %{provider: provider, storage: storage}
    end

    test "delegates to SubmitVerificationDocument use case", %{
      provider: provider,
      storage: storage
    } do
      params = %{
        provider_profile_id: provider.id,
        document_type: "background_check",
        file_binary: "content",
        original_filename: "doc.pdf",
        storage_opts: [adapter: StubStorageAdapter, agent: storage]
      }

      assert {:ok, %VerificationDocument{} = doc} = Provider.submit_verification_document(params)
      assert doc.provider_profile_id == provider.id
      assert doc.status == :pending
    end
  end

  describe "approve_verification_document/2" do
    setup do
      provider = ProviderFixtures.provider_profile_fixture()
      admin = AccountsFixtures.user_fixture(%{is_admin: true})
      {:ok, doc} = create_pending_document(provider.id)
      %{provider: provider, admin: admin, document: doc}
    end

    test "delegates with correct arg mapping", %{admin: admin, document: doc} do
      assert {:ok, %VerificationDocument{} = approved} =
               Provider.approve_verification_document(doc.id, admin.id)

      assert approved.status == :approved
      assert approved.reviewed_by_id == admin.id
    end
  end

  describe "reject_verification_document/3" do
    setup do
      provider = ProviderFixtures.provider_profile_fixture()
      admin = AccountsFixtures.user_fixture(%{is_admin: true})
      {:ok, doc} = create_pending_document(provider.id)
      %{provider: provider, admin: admin, document: doc}
    end

    test "delegates with correct arg mapping", %{admin: admin, document: doc} do
      assert {:ok, %VerificationDocument{} = rejected} =
               Provider.reject_verification_document(doc.id, admin.id, "Expired document")

      assert rejected.status == :rejected
      assert rejected.rejection_reason == "Expired document"
    end
  end

  describe "get_provider_verification_documents/1" do
    setup do
      provider = ProviderFixtures.provider_profile_fixture()
      {:ok, doc} = create_pending_document(provider.id)
      %{provider: provider, document: doc}
    end

    test "returns documents for provider", %{provider: provider, document: doc} do
      assert {:ok, docs} = Provider.get_provider_verification_documents(provider.id)
      assert length(docs) == 1
      assert Enum.at(docs, 0).id == doc.id
    end

    test "returns empty list for provider with no documents" do
      other_provider = ProviderFixtures.provider_profile_fixture()
      assert {:ok, []} = Provider.get_provider_verification_documents(other_provider.id)
    end
  end

  describe "list_pending_verification_documents/0" do
    setup do
      provider = ProviderFixtures.provider_profile_fixture()
      {:ok, doc} = create_pending_document(provider.id)
      %{provider: provider, document: doc}
    end

    test "returns pending documents", %{document: doc} do
      assert {:ok, docs} = Provider.list_pending_verification_documents()
      assert Enum.any?(docs, fn d -> d.id == doc.id end)
    end
  end

  # Admin Verification Review Functions

  describe "list_verification_documents_for_admin/1" do
    setup do
      provider = ProviderFixtures.provider_profile_fixture(%{business_name: "Admin Test Corp"})
      {:ok, pending} = create_pending_document(provider.id)

      admin = AccountsFixtures.user_fixture(%{is_admin: true})
      {:ok, approved} = create_and_approve_document(provider.id, admin.id)

      %{provider: provider, pending: pending, approved: approved}
    end

    test "returns all documents with provider business names when status is nil", %{
      pending: pending,
      approved: approved
    } do
      assert {:ok, results} = Provider.list_verification_documents_for_admin(nil)

      ids = Enum.map(results, fn %{document: d} -> d.id end)
      assert pending.id in ids
      assert approved.id in ids

      # Verify the result shape includes provider business name
      result = Enum.find(results, fn %{document: d} -> d.id == pending.id end)
      assert result.provider_business_name == "Admin Test Corp"
    end

    test "filters by pending status", %{pending: pending, approved: approved} do
      assert {:ok, results} = Provider.list_verification_documents_for_admin(:pending)

      ids = Enum.map(results, fn %{document: d} -> d.id end)
      assert pending.id in ids
      refute approved.id in ids
    end

    test "filters by approved status", %{pending: pending, approved: approved} do
      assert {:ok, results} = Provider.list_verification_documents_for_admin(:approved)

      ids = Enum.map(results, fn %{document: d} -> d.id end)
      refute pending.id in ids
      assert approved.id in ids
    end

    test "returns empty list when no documents match" do
      assert {:ok, []} = Provider.list_verification_documents_for_admin(:rejected)
    end

    test "pending documents are ordered oldest first (FIFO)" do
      provider = ProviderFixtures.provider_profile_fixture()
      {:ok, first} = create_pending_document(provider.id)

      # Small delay to ensure different timestamps
      {:ok, second} = create_pending_document(provider.id)

      assert {:ok, results} = Provider.list_verification_documents_for_admin(:pending)
      pending_ids = Enum.map(results, fn %{document: d} -> d.id end)

      first_idx = Enum.find_index(pending_ids, &(&1 == first.id))
      second_idx = Enum.find_index(pending_ids, &(&1 == second.id))
      assert first_idx < second_idx
    end
  end

  describe "get_verification_document_for_admin/1" do
    setup do
      provider = ProviderFixtures.provider_profile_fixture(%{business_name: "Review Corp"})
      {:ok, doc} = create_pending_document(provider.id)
      %{provider: provider, document: doc}
    end

    test "returns document with provider business name", %{document: doc} do
      assert {:ok, result} = Provider.get_verification_document_for_admin(doc.id)
      assert result.document.id == doc.id
      assert result.provider_business_name == "Review Corp"
    end

    test "returns {:error, :not_found} for nonexistent ID" do
      assert {:error, :not_found} =
               Provider.get_verification_document_for_admin(Ecto.UUID.generate())
    end
  end

  # Provider Verification Functions

  describe "verify_provider/2" do
    setup do
      setup_test_integration_events()
      provider = ProviderFixtures.provider_profile_fixture()
      admin = AccountsFixtures.user_fixture(%{is_admin: true})
      %{provider: provider, admin: admin}
    end

    test "delegates with correct arg mapping", %{provider: provider, admin: admin} do
      assert {:ok, %ProviderProfile{} = verified} =
               Provider.verify_provider(provider.id, admin.id)

      assert verified.verified == true
      assert verified.verified_at != nil
    end
  end

  describe "unverify_provider/2" do
    setup do
      setup_test_integration_events()
      provider = ProviderFixtures.provider_profile_fixture()
      admin = AccountsFixtures.user_fixture(%{is_admin: true})
      # First verify the provider so we can unverify
      {:ok, _} = Provider.verify_provider(provider.id, admin.id)
      %{provider: provider, admin: admin}
    end

    test "delegates with correct arg mapping", %{provider: provider, admin: admin} do
      assert {:ok, %ProviderProfile{} = unverified} =
               Provider.unverify_provider(provider.id, admin.id)

      assert unverified.verified == false
      assert unverified.verified_at == nil
    end
  end

  describe "list_verified_provider_ids/0" do
    test "returns verified provider IDs" do
      setup_test_integration_events()
      provider = ProviderFixtures.provider_profile_fixture()
      admin = AccountsFixtures.user_fixture(%{is_admin: true})

      {:ok, _} = Provider.verify_provider(provider.id, admin.id)

      assert {:ok, ids} = Provider.list_verified_provider_ids()
      assert provider.id in ids
    end
  end

  # Test Helpers

  defp create_pending_document(provider_id) do
    %{
      provider_profile_id: provider_id,
      document_type: "business_registration",
      file_url: "verification-docs/test.pdf",
      original_filename: "doc.pdf"
    }
    |> VerificationDocument.create_changeset()
    |> KlassHero.Repo.insert()
  end

  defp create_and_approve_document(provider_id, admin_id) do
    {:ok, doc} = create_pending_document(provider_id)
    Provider.approve_verification_document(doc.id, admin_id)
  end
end
