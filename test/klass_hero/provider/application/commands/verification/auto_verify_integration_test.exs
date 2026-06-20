defmodule KlassHero.Provider.Application.Commands.Verification.AutoVerifyIntegrationTest do
  @moduledoc """
  Integration test for the full flow through the Vetting engine: approving every required
  document step verifies the provider; rejecting a step's document unverifies it.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.EventTestHelper

  alias KlassHero.AccountsFixtures
  alias KlassHero.Provider.Adapters.Driven.Persistence.Repositories.ProviderProfileRepository
  alias KlassHero.Provider.Adapters.Driven.Persistence.Repositories.VettingCaseRepository
  alias KlassHero.Provider.Application.Commands.Verification.ApproveVerificationDocument
  alias KlassHero.Provider.Application.Commands.Verification.RejectVerificationDocument
  alias KlassHero.Provider.Domain.Models.VettingCase
  alias KlassHero.ProviderFixtures

  # The individual track's three document steps (identity is the fourth required step, completed
  # out-of-band via Stripe and pre-approved in setup so these tests isolate the document flow).
  @individual_doc_types ~w(experience_validation background_check safeguarding_certificate)

  setup do
    setup_test_integration_events()
    provider = ProviderFixtures.provider_profile_fixture()
    admin = AccountsFixtures.user_fixture(%{is_admin: true})
    approve_identity_step(provider.id, admin.id)
    %{provider: provider, admin: admin}
  end

  defp approve_identity_step(provider_id, admin_id) do
    {:ok, case_} = VettingCaseRepository.get_by_provider(provider_id)
    {:ok, updated} = VettingCase.approve_step(case_, :identity, admin_id, Ecto.UUID.generate())
    {:ok, _} = VettingCaseRepository.update(updated)
  end

  defp approve_doc(provider, admin, document_type) do
    doc = ProviderFixtures.verification_document_fixture(provider_id: provider.id, document_type: document_type)
    ApproveVerificationDocument.execute(%{document_id: doc.id, reviewer_id: admin.id})
  end

  defp verified?(provider) do
    {:ok, profile} = ProviderProfileRepository.get(provider.id)
    profile.verified
  end

  describe "full approval flow" do
    test "verifies only once every required document step is approved", %{provider: provider, admin: admin} do
      [first, second, last] = @individual_doc_types

      approve_doc(provider, admin, first)
      refute verified?(provider)

      approve_doc(provider, admin, second)
      refute verified?(provider)

      approve_doc(provider, admin, last)
      assert verified?(provider)
    end

    test "a document type outside the track never verifies", %{provider: provider, admin: admin} do
      approve_doc(provider, admin, "tax_certificate")
      refute verified?(provider)
    end
  end

  describe "rejection after verification" do
    test "rejecting a required step's document unverifies the provider", %{provider: provider, admin: admin} do
      for document_type <- @individual_doc_types, do: approve_doc(provider, admin, document_type)
      assert verified?(provider)

      # A fresh background-check document is submitted and rejected, resetting that step.
      doc = ProviderFixtures.verification_document_fixture(provider_id: provider.id, document_type: "background_check")
      RejectVerificationDocument.execute(%{document_id: doc.id, reviewer_id: admin.id, reason: "Expired"})

      refute verified?(provider)
    end
  end
end
