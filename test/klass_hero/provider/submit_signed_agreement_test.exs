defmodule KlassHero.Provider.SubmitSignedAgreementTest do
  @moduledoc """
  The signed-agreement command: signing persists a SignedAgreement and auto-approves the matching
  step (no admin review), for both the Community Standards Agreement (`:community_agreement`, B4)
  and the Staff Compliance Declaration (`:staff_attestation`, B5). When it is the last outstanding
  step, the provider becomes verified. Business agreements are signed by the responsible person and
  stamped `:business`; the command fails closed when no responsible person is on record.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.EventTestHelper

  alias KlassHero.AccountsFixtures
  alias KlassHero.Provider
  alias KlassHero.Provider.SubmitSignedAgreement
  alias KlassHero.Provider.VerificationDocument
  alias KlassHero.Provider.Vetting
  alias KlassHero.Provider.VettingCase
  alias KlassHero.ProviderFixtures

  # Derived from the engine so a new document step is covered here automatically.
  @individual_doc_types VerificationDocument.valid_document_types(:individual)

  # Both business-track signed-agreement steps, with the version each policy stamps. The step key
  # equals the kind atom for both, so one helper reads either step's status.
  @business_kinds [
    {:community_agreement, "1.0"},
    {:staff_attestation, "1.0-provisional"}
  ]

  setup do
    setup_test_integration_events()
    provider = ProviderFixtures.provider_profile_fixture()
    clear_integration_events()
    %{provider: provider}
  end

  defp step_status(provider_id, step_key) do
    {:ok, case_} = Vetting.get_case_for_provider(provider_id)
    Enum.find(case_.steps, &(&1.key == step_key)).status
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

  describe "execute/1 — community agreement (individual track)" do
    test "persists a signed agreement and auto-approves the step", %{provider: provider} do
      assert :not_started = step_status(provider.id, :community_agreement)

      assert {:ok, agreement} =
               SubmitSignedAgreement.execute(%{
                 kind: :community_agreement,
                 provider_id: provider.id,
                 signed_by_name: "Lena Hartmann"
               })

      assert agreement.kind == :community_agreement
      assert agreement.signed_by_name == "Lena Hartmann"
      assert agreement.version == "1.0"

      assert :approved = step_status(provider.id, :community_agreement)
      assert %{id: id} = Provider.get_latest_community_agreement(provider.id)
      assert id == agreement.id
    end

    test "does not verify the provider while other steps are still pending", %{provider: provider} do
      assert {:ok, _} =
               SubmitSignedAgreement.execute(%{
                 kind: :community_agreement,
                 provider_id: provider.id,
                 signed_by_name: "Lena"
               })

      refute verified?(provider.id)
      assert_no_integration_events_published()
    end

    test "verifies the provider when the agreement is the final outstanding step", %{provider: provider} do
      approve_all_but_agreement(provider.id)
      clear_integration_events()

      assert {:ok, _} =
               SubmitSignedAgreement.execute(%{
                 kind: :community_agreement,
                 provider_id: provider.id,
                 signed_by_name: "Lena"
               })

      assert verified?(provider.id)
      assert_integration_event_published(:provider_verified)
    end

    test "rejects a blank signer name", %{provider: provider} do
      assert {:error, errors} =
               SubmitSignedAgreement.execute(%{
                 kind: :community_agreement,
                 provider_id: provider.id,
                 signed_by_name: "  "
               })

      assert Keyword.has_key?(errors, :signed_by_name)
      assert :not_started = step_status(provider.id, :community_agreement)
    end

    test "stamps the individual's entity_type on the agreement", %{provider: provider} do
      assert {:ok, agreement} =
               SubmitSignedAgreement.execute(%{
                 kind: :community_agreement,
                 provider_id: provider.id,
                 signed_by_name: "Lena"
               })

      assert agreement.entity_type == :individual
    end
  end

  describe "execute/1 — business track (community agreement B4 + staff attestation B5)" do
    setup do
      provider = ProviderFixtures.provider_profile_fixture(entity_type: :business)
      {:ok, :set} = Provider.set_responsible_person(provider.id, "Jane Smith", "Owner")
      %{provider: provider}
    end

    test "signs each business agreement as the responsible person, stamping kind + version + :business",
         %{provider: provider} do
      for {kind, version} <- @business_kinds do
        assert {:ok, agreement} =
                 SubmitSignedAgreement.execute(%{
                   kind: kind,
                   provider_id: provider.id,
                   signed_by_name: "Logged-In Bystander"
                 }),
               "expected #{kind} to sign"

        assert agreement.kind == kind, "kind for #{kind}"
        assert agreement.version == version, "version for #{kind}"
        assert agreement.signed_by_name == "Jane Smith", "signer for #{kind}"
        assert agreement.entity_type == :business, "entity_type for #{kind}"
        assert :approved = step_status(provider.id, kind)
      end
    end

    test "fails closed for any business agreement when there is no responsible person" do
      provider = ProviderFixtures.provider_profile_fixture(entity_type: :business)

      for {kind, _version} <- @business_kinds do
        assert {:error, :missing_responsible_person} =
                 SubmitSignedAgreement.execute(%{
                   kind: kind,
                   provider_id: provider.id,
                   signed_by_name: "Anyone"
                 }),
               "expected #{kind} to fail closed"

        assert :not_started = step_status(provider.id, kind)
      end
    end
  end
end
