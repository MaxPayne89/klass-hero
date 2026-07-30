defmodule KlassHero.Provider.Adapters.Driving.Events.EventHandlers.AdvanceVettingStepOnDocumentReviewTest do
  use KlassHero.DataCase, async: true

  import ExUnit.CaptureLog
  import KlassHero.EventTestHelper

  alias KlassHero.AccountsFixtures
  alias KlassHero.Provider.Adapters.Driving.Events.EventHandlers.AdvanceVettingStepOnDocumentReview
  alias KlassHero.Provider.VerificationDocument
  alias KlassHero.Provider.Vetting
  alias KlassHero.Provider.VettingCase
  alias KlassHero.ProviderFixtures
  alias KlassHero.Shared.Domain.Events.Event

  # The individual track's document steps, derived from the engine so a new document
  # step is exercised here automatically (see Vetting.track(:individual)).
  @individual_doc_types VerificationDocument.valid_document_types(:individual)

  setup do
    setup_test_integration_events()
    provider = ProviderFixtures.provider_profile_fixture()
    admin = AccountsFixtures.user_fixture(%{is_admin: true})
    clear_integration_events()
    %{provider: provider, admin: admin}
  end

  describe "handle/1 for :verification_document_approved" do
    test "verifies the provider once every required step is approved", %{provider: provider, admin: admin} do
      # Identity + community agreement are non-document steps; approve them directly so
      # the final document approval crosses the case to :verified.
      approve_non_document_steps(provider.id, admin.id)

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

    test "ignores and logs a document type that is not part of the provider's track", %{
      provider: provider,
      admin: admin
    } do
      log =
        capture_log(fn ->
          assert :ok =
                   AdvanceVettingStepOnDocumentReview.handle(approved_event(provider.id, admin.id, "tax_certificate"))
        end)

      assert log =~ "No vetting step consumes document_type=\"tax_certificate\""
      assert_no_integration_events_published()
    end
  end

  describe "handle/1 for :verification_document_rejected" do
    test "does not unverify a provider that was never verified", %{provider: provider, admin: admin} do
      assert :ok =
               AdvanceVettingStepOnDocumentReview.handle(rejected_event(provider.id, admin.id, "background_check"))

      assert_no_integration_events_published()
    end

    test "unverifies the provider when an approved step is later rejected", %{provider: provider, admin: admin} do
      approve_non_document_steps(provider.id, admin.id)

      for document_type <- @individual_doc_types do
        AdvanceVettingStepOnDocumentReview.handle(approved_event(provider.id, admin.id, document_type))
      end

      clear_integration_events()

      assert :ok =
               AdvanceVettingStepOnDocumentReview.handle(rejected_event(provider.id, admin.id, "background_check"))

      assert_integration_event_published(:provider_unverified)
    end
  end

  # Pre-approves the individual track's non-document steps (identity + community
  # agreement) so approving the document steps is what crosses the case to :verified.
  defp approve_non_document_steps(provider_id, admin_id) do
    {:ok, case_} = Vetting.get_case_for_provider(provider_id)
    {:ok, with_identity} = VettingCase.approve_step(case_, :identity, admin_id, Ecto.UUID.generate())
    {:ok, updated} = VettingCase.auto_approve_step(with_identity, :community_agreement, Ecto.UUID.generate())
    {:ok, _} = Vetting.save_case(updated)
  end

  defp approved_event(provider_id, reviewer_id, document_type) do
    Event.new(:verification_document_approved, :provider, :verification_document, Ecto.UUID.generate(), %{
      provider_id: provider_id,
      reviewer_id: reviewer_id,
      document_type: document_type,
      document_id: Ecto.UUID.generate()
    })
  end

  defp rejected_event(provider_id, reviewer_id, document_type) do
    Event.new(:verification_document_rejected, :provider, :verification_document, Ecto.UUID.generate(), %{
      provider_id: provider_id,
      reviewer_id: reviewer_id,
      document_type: document_type,
      document_id: Ecto.UUID.generate()
    })
  end
end
