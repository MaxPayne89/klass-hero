defmodule KlassHero.Provider.Adapters.Driving.Events.EventHandlers.AdvanceVettingStepOnDocumentReviewTest do
  use KlassHero.DataCase, async: true

  import KlassHero.EventTestHelper

  alias KlassHero.AccountsFixtures
  alias KlassHero.Provider.Adapters.Driving.Events.EventHandlers.AdvanceVettingStepOnDocumentReview
  alias KlassHero.ProviderFixtures
  alias KlassHero.Shared.Domain.Events.DomainEvent

  # The individual track's document steps (see Vetting.track(:individual)).
  @individual_doc_types ~w(experience_validation background_check safeguarding_certificate)

  setup do
    setup_test_integration_events()
    provider = ProviderFixtures.provider_profile_fixture()
    admin = AccountsFixtures.user_fixture(%{is_admin: true})
    clear_integration_events()
    %{provider: provider, admin: admin}
  end

  describe "handle/1 for :verification_document_approved" do
    test "verifies the provider once every required step is approved", %{provider: provider, admin: admin} do
      for document_type <- @individual_doc_types do
        assert :ok = AdvanceVettingStepOnDocumentReview.handle(approved_event(provider.id, admin.id, document_type))
      end

      assert_integration_event_published(:provider_verified)
    end

    test "does not verify while a required step is still pending", %{provider: provider, admin: admin} do
      assert :ok =
               AdvanceVettingStepOnDocumentReview.handle(approved_event(provider.id, admin.id, "experience_validation"))

      assert_no_integration_events_published()
    end

    test "ignores a document type that is not part of the provider's track", %{provider: provider, admin: admin} do
      assert :ok = AdvanceVettingStepOnDocumentReview.handle(approved_event(provider.id, admin.id, "tax_certificate"))

      assert_no_integration_events_published()
    end
  end

  describe "handle/1 for :verification_document_rejected" do
    test "unverifies the provider when an approved step is later rejected", %{provider: provider, admin: admin} do
      for document_type <- @individual_doc_types do
        AdvanceVettingStepOnDocumentReview.handle(approved_event(provider.id, admin.id, document_type))
      end

      clear_integration_events()

      assert :ok =
               AdvanceVettingStepOnDocumentReview.handle(rejected_event(provider.id, admin.id, "background_check"))

      assert_integration_event_published(:provider_unverified)
    end
  end

  defp approved_event(provider_id, reviewer_id, document_type) do
    DomainEvent.new(:verification_document_approved, Ecto.UUID.generate(), :verification_document, %{
      provider_id: provider_id,
      reviewer_id: reviewer_id,
      document_type: document_type,
      document_id: Ecto.UUID.generate()
    })
  end

  defp rejected_event(provider_id, reviewer_id, document_type) do
    DomainEvent.new(:verification_document_rejected, Ecto.UUID.generate(), :verification_document, %{
      provider_id: provider_id,
      reviewer_id: reviewer_id,
      document_type: document_type,
      document_id: Ecto.UUID.generate()
    })
  end
end
