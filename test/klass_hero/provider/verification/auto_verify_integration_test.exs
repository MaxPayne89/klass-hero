defmodule KlassHero.Provider.Verification.AutoVerifyIntegrationTest do
  @moduledoc """
  Integration test for the step-engine boundary effect on `ProviderProfile.verified`:
  the provider becomes verified only when EVERY step of its track is approved, and is
  unverified when an approved step is later rejected.

  Drives the engine through `Vetting.advance_step_for_document/4` (the document steps)
  plus direct approval of the non-document steps (identity + community agreement),
  since the individual-track document types are not submittable through the real upload
  path until the `DocumentType` enum widens (Slice 3).
  """

  use KlassHero.DataCase, async: true

  alias KlassHero.AccountsFixtures
  alias KlassHero.Provider
  alias KlassHero.Provider.VerificationDocument
  alias KlassHero.Provider.Vetting
  alias KlassHero.Provider.VettingCase
  alias KlassHero.ProviderFixtures

  @individual_doc_types VerificationDocument.valid_document_types(:individual)

  setup do
    provider = ProviderFixtures.provider_profile_fixture()
    admin = AccountsFixtures.user_fixture(%{is_admin: true})
    %{provider: provider, admin: admin}
  end

  describe "full approval flow" do
    test "provider is not verified until every track step is approved", %{provider: provider, admin: admin} do
      approve_non_document_steps(provider.id, admin.id)

      # Approve all but the last document step — still not verified.
      [last | rest] = Enum.reverse(@individual_doc_types)

      for document_type <- rest do
        approve_document_step(provider.id, admin.id, document_type)
      end

      assert {:ok, %{verified: false}} = Provider.get_provider_profile(provider.id)

      # The final step crosses the case to verified.
      approve_document_step(provider.id, admin.id, last)

      assert {:ok, %{verified: true, verified_at: verified_at}} = Provider.get_provider_profile(provider.id)
      assert verified_at != nil
    end
  end

  describe "rejection after verification" do
    test "rejecting an approved step unverifies the provider", %{provider: provider, admin: admin} do
      approve_non_document_steps(provider.id, admin.id)

      for document_type <- @individual_doc_types do
        approve_document_step(provider.id, admin.id, document_type)
      end

      assert {:ok, %{verified: true}} = Provider.get_provider_profile(provider.id)

      assert :ok = Vetting.reset_step_for_document(provider.id, admin.id, "background_check")

      assert {:ok, %{verified: false}} = Provider.get_provider_profile(provider.id)
    end
  end

  defp approve_non_document_steps(provider_id, admin_id) do
    {:ok, case_} = Vetting.get_case_for_provider(provider_id)
    {:ok, with_identity} = VettingCase.approve_step(case_, :identity, admin_id, Ecto.UUID.generate())
    {:ok, updated} = VettingCase.auto_approve_step(with_identity, :community_agreement, Ecto.UUID.generate())
    {:ok, _} = Vetting.save_case(updated)
  end

  defp approve_document_step(provider_id, reviewer_id, document_type) do
    assert :ok =
             Vetting.advance_step_for_document(provider_id, reviewer_id, document_type, Ecto.UUID.generate())
  end
end
