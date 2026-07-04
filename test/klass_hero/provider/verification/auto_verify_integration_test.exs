defmodule KlassHero.Provider.Verification.AutoVerifyIntegrationTest do
  @moduledoc """
  Integration test for the full flow: approve all docs -> provider verified.
  Reject a doc -> provider unverified.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.EventTestHelper

  alias KlassHero.AccountsFixtures
  alias KlassHero.Provider
  alias KlassHero.ProviderFixtures

  setup do
    setup_test_integration_events()
    provider = ProviderFixtures.provider_profile_fixture()
    admin = AccountsFixtures.user_fixture(%{is_admin: true})
    %{provider: provider, admin: admin}
  end

  describe "full approval flow" do
    test "approving all documents auto-verifies provider", %{provider: provider, admin: admin} do
      doc1 =
        ProviderFixtures.verification_document_fixture(
          provider_id: provider.id,
          document_type: "business_registration"
        )

      doc2 =
        ProviderFixtures.verification_document_fixture(
          provider_id: provider.id,
          document_type: "insurance_certificate"
        )

      # Approve first doc -- provider should NOT be verified yet
      KlassHero.Provider.approve_verification_document(doc1.id, admin.id)

      {:ok, profile} = Provider.get_provider_profile(provider.id)
      assert profile.verified == false

      # Approve second doc -- NOW provider should be verified
      KlassHero.Provider.approve_verification_document(doc2.id, admin.id)

      {:ok, profile} = Provider.get_provider_profile(provider.id)
      assert profile.verified == true
      assert profile.verified_at != nil
    end

    test "single document approval auto-verifies provider", %{provider: provider, admin: admin} do
      doc =
        ProviderFixtures.verification_document_fixture(
          provider_id: provider.id,
          document_type: "business_registration"
        )

      KlassHero.Provider.approve_verification_document(doc.id, admin.id)

      {:ok, profile} = Provider.get_provider_profile(provider.id)
      assert profile.verified == true
    end
  end

  describe "rejection after verification" do
    test "rejecting a doc after verification auto-unverifies provider", %{
      provider: provider,
      admin: admin
    } do
      doc1 =
        ProviderFixtures.verification_document_fixture(
          provider_id: provider.id,
          document_type: "business_registration"
        )

      doc2 =
        ProviderFixtures.verification_document_fixture(
          provider_id: provider.id,
          document_type: "insurance_certificate"
        )

      # Approve both to get verified
      KlassHero.Provider.approve_verification_document(doc1.id, admin.id)
      KlassHero.Provider.approve_verification_document(doc2.id, admin.id)

      {:ok, profile} = Provider.get_provider_profile(provider.id)
      assert profile.verified == true

      # Now submit a new doc and have it rejected
      doc3 =
        ProviderFixtures.verification_document_fixture(
          provider_id: provider.id,
          document_type: "tax_certificate"
        )

      KlassHero.Provider.reject_verification_document(doc3.id, admin.id, "Expired")

      {:ok, profile} = Provider.get_provider_profile(provider.id)
      assert profile.verified == false
    end
  end
end
