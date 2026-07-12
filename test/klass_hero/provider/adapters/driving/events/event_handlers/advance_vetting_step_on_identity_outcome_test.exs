defmodule KlassHero.Provider.Adapters.Driving.Events.EventHandlers.AdvanceVettingStepOnIdentityOutcomeTest do
  use KlassHero.DataCase, async: true

  import KlassHero.EventTestHelper

  alias KlassHero.AccountsFixtures
  alias KlassHero.Provider.Adapters.Driving.Events.EventHandlers.AdvanceVettingStepOnIdentityOutcome
  alias KlassHero.Provider.VerificationDocument
  alias KlassHero.Provider.Vetting
  alias KlassHero.Provider.VettingCase
  alias KlassHero.ProviderFixtures
  alias KlassHero.Shared.Domain.Events.DomainEvent

  # Derived from the engine so a new document step is approved here automatically.
  @individual_doc_types VerificationDocument.valid_document_types(:individual)

  setup do
    setup_test_integration_events()
    provider = ProviderFixtures.provider_profile_fixture()
    clear_integration_events()
    %{provider: provider}
  end

  describe "handle/1 for :identity_verification_passed" do
    test "approves the identity step", %{provider: provider} do
      assert :ok = AdvanceVettingStepOnIdentityOutcome.handle(passed_event(provider.id))

      {:ok, case_} = Vetting.get_case_for_provider(provider.id)
      identity = Enum.find(case_.steps, &(&1.key == :identity))
      assert identity.status == :approved
      assert identity.reviewed_by_id == nil
    end

    test "does not verify the provider while document steps are still pending", %{provider: provider} do
      assert :ok = AdvanceVettingStepOnIdentityOutcome.handle(passed_event(provider.id))
      assert_no_integration_events_published()
    end

    test "verifies the provider when identity is the last outstanding step", %{provider: provider} do
      approve_all_but_identity(provider.id)

      assert :ok = AdvanceVettingStepOnIdentityOutcome.handle(passed_event(provider.id))
      assert_integration_event_published(:provider_verified)
    end
  end

  describe "handle/1 for :identity_verification_failed" do
    test "resets the identity step", %{provider: provider} do
      AdvanceVettingStepOnIdentityOutcome.handle(passed_event(provider.id))

      assert :ok = AdvanceVettingStepOnIdentityOutcome.handle(failed_event(provider.id))

      {:ok, case_} = Vetting.get_case_for_provider(provider.id)
      identity = Enum.find(case_.steps, &(&1.key == :identity))
      assert identity.status == :not_started
    end

    test "unverifies a verified provider", %{provider: provider} do
      approve_all_but_identity(provider.id)
      AdvanceVettingStepOnIdentityOutcome.handle(passed_event(provider.id))
      clear_integration_events()

      assert :ok = AdvanceVettingStepOnIdentityOutcome.handle(failed_event(provider.id))
      assert_integration_event_published(:provider_unverified)
    end

    test "does not unverify a provider that was never verified", %{provider: provider} do
      AdvanceVettingStepOnIdentityOutcome.handle(passed_event(provider.id))
      clear_integration_events()

      assert :ok = AdvanceVettingStepOnIdentityOutcome.handle(failed_event(provider.id))
      assert_no_integration_events_published()
    end
  end

  describe "handle/1 for an unknown provider" do
    test "is a no-op" do
      assert :ok = AdvanceVettingStepOnIdentityOutcome.handle(passed_event(Ecto.UUID.generate()))
      assert_no_integration_events_published()
    end
  end

  describe "handle/1 for a business provider" do
    test "approves the responsible-person identity step on a passed outcome" do
      business = ProviderFixtures.provider_profile_fixture(entity_type: "business")
      clear_integration_events()

      assert :ok = AdvanceVettingStepOnIdentityOutcome.handle(passed_event(business.id))

      {:ok, case_} = Vetting.get_case_for_provider(business.id)
      identity = Enum.find(case_.steps, &(&1.key == :responsible_person_identity))
      assert identity.status == :approved
      assert identity.reviewed_by_id == nil
    end
  end

  # Approves every individual-track step except identity (the document steps and the
  # auto-approving community agreement), leaving identity as the last step to verify.
  defp approve_all_but_identity(provider_id) do
    admin = AccountsFixtures.user_fixture(%{is_admin: true})
    {:ok, case_} = Vetting.get_case_for_provider(provider_id)

    with_docs =
      Enum.reduce(@individual_doc_types, case_, fn doc_type, acc ->
        key = VettingCase.step_key_for_document(acc, doc_type)
        {:ok, advanced} = VettingCase.approve_step(acc, key, admin.id, Ecto.UUID.generate())
        advanced
      end)

    {:ok, updated} = VettingCase.auto_approve_step(with_docs, :community_agreement, Ecto.UUID.generate())

    {:ok, _} = Vetting.save_case(updated)
  end

  defp passed_event(provider_id) do
    DomainEvent.new(:identity_verification_passed, Ecto.UUID.generate(), :identity_verification, %{
      provider_id: provider_id,
      identity_verification_id: Ecto.UUID.generate(),
      stripe_session_id: "vs_x",
      failure_reason: nil
    })
  end

  defp failed_event(provider_id) do
    DomainEvent.new(:identity_verification_failed, Ecto.UUID.generate(), :identity_verification, %{
      provider_id: provider_id,
      identity_verification_id: Ecto.UUID.generate(),
      stripe_session_id: "vs_x",
      failure_reason: "under_18"
    })
  end
end
