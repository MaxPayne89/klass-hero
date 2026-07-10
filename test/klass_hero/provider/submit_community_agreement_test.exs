defmodule KlassHero.Provider.SubmitCommunityAgreementTest do
  @moduledoc """
  The Community Standards Agreement command: signing persists a SignedAgreement and auto-approves
  the :community_agreement step (no admin review). When it is the last outstanding step, the
  provider becomes verified.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.EventTestHelper

  alias KlassHero.AccountsFixtures
  alias KlassHero.Provider
  alias KlassHero.Provider.SubmitCommunityAgreement
  alias KlassHero.Provider.VerificationDocument
  alias KlassHero.Provider.Vetting
  alias KlassHero.Provider.VettingCase
  alias KlassHero.ProviderFixtures

  # Derived from the engine so a new document step is covered here automatically.
  @individual_doc_types VerificationDocument.valid_document_types(:individual)

  setup do
    setup_test_integration_events()
    provider = ProviderFixtures.provider_profile_fixture()
    clear_integration_events()
    %{provider: provider}
  end

  defp agreement_step_status(provider_id) do
    {:ok, case_} = Vetting.get_case_for_provider(provider_id)
    Enum.find(case_.steps, &(&1.key == :community_agreement)).status
  end

  # Approves every individual-track step except community_agreement (the four document steps and
  # identity), leaving the agreement as the last step to verify.
  defp approve_all_but_agreement(provider_id) do
    admin = AccountsFixtures.user_fixture(%{is_admin: true})
    {:ok, case_} = Vetting.get_case_for_provider(provider_id)

    with_docs =
      Enum.reduce(@individual_doc_types, case_, fn doc_type, acc ->
        key = VettingCase.step_key_for_document(acc, doc_type)
        {:ok, advanced} = VettingCase.approve_step(acc, key, admin.id, Ecto.UUID.generate())
        advanced
      end)

    {:ok, updated} = VettingCase.auto_approve_step(with_docs, :identity, Ecto.UUID.generate())
    {:ok, _} = Vetting.save_case(updated)
  end

  defp verified?(provider_id) do
    {:ok, profile} = Provider.get_provider_profile(provider_id)
    profile.verified
  end

  describe "execute/1" do
    test "persists a signed agreement and auto-approves the step", %{provider: provider} do
      assert :not_started = agreement_step_status(provider.id)

      assert {:ok, agreement} =
               SubmitCommunityAgreement.execute(%{
                 provider_id: provider.id,
                 signed_by_name: "Lena Hartmann"
               })

      assert agreement.kind == :community_agreement
      assert agreement.signed_by_name == "Lena Hartmann"
      assert agreement.version == "1.0"

      assert :approved = agreement_step_status(provider.id)
      assert %{id: id} = Provider.get_latest_community_agreement(provider.id)
      assert id == agreement.id
    end

    test "does not verify the provider while other steps are still pending", %{provider: provider} do
      assert {:ok, _} =
               SubmitCommunityAgreement.execute(%{provider_id: provider.id, signed_by_name: "Lena"})

      refute verified?(provider.id)
      assert_no_integration_events_published()
    end

    test "verifies the provider when the agreement is the final outstanding step", %{provider: provider} do
      approve_all_but_agreement(provider.id)
      clear_integration_events()

      assert {:ok, _} =
               SubmitCommunityAgreement.execute(%{provider_id: provider.id, signed_by_name: "Lena"})

      assert verified?(provider.id)
      assert_integration_event_published(:provider_verified)
    end

    test "rejects a blank signer name", %{provider: provider} do
      assert {:error, errors} =
               SubmitCommunityAgreement.execute(%{provider_id: provider.id, signed_by_name: "  "})

      assert Keyword.has_key?(errors, :signed_by_name)
      assert :not_started = agreement_step_status(provider.id)
    end
  end
end
