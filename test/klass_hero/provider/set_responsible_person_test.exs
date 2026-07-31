defmodule KlassHero.Provider.SetResponsiblePersonTest do
  @moduledoc """
  The `set_responsible_person/3` command (ADR-0010): the single idempotent mutator of a
  business's Responsible Person and the sole vetting-reset trigger. Exact-match (normalized)
  change-detection returns `:unchanged | :set | :changed`; only `:changed` resets the
  `:responsible_person_identity` step (cascading to the two agreements) and unverifies the
  business if it was verified. B2/B3 (registration, insurance) never reset.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.EventTestHelper

  alias KlassHero.AccountsFixtures
  alias KlassHero.Provider
  alias KlassHero.Provider.StripeIdentity
  alias KlassHero.Provider.VerificationDocument
  alias KlassHero.Provider.Vetting
  alias KlassHero.Provider.VettingCase
  alias KlassHero.ProviderFixtures

  @return_url "https://klasshero.test/provider/verification"

  setup do
    setup_test_integration_events()
    provider = ProviderFixtures.provider_profile_fixture(entity_type: "business")
    clear_integration_events()
    %{provider: provider}
  end

  defp reload(provider_id) do
    {:ok, profile} = Provider.get_provider_profile(provider_id)
    profile
  end

  defp step_status(provider_id, key) do
    {:ok, case_} = Vetting.get_case_for_provider(provider_id)
    Enum.find(case_.steps, &(&1.key == key)).status
  end

  # Approves all five business steps and persists the case at :verified.
  defp approve_all_business_steps(provider_id) do
    admin = AccountsFixtures.user_fixture(%{is_admin: true})
    {:ok, case_} = Vetting.get_case_for_provider(provider_id)
    {:ok, with_identity} = VettingCase.auto_approve_step(case_, :responsible_person_identity, Ecto.UUID.generate())

    with_docs =
      Enum.reduce(VerificationDocument.valid_document_types(:business), with_identity, fn doc_type, acc ->
        key = VettingCase.step_key_for_document(acc, doc_type)
        {:ok, advanced} = VettingCase.approve_step(acc, key, admin.id, Ecto.UUID.generate())
        advanced
      end)

    {:ok, with_ca} = VettingCase.auto_approve_step(with_docs, :community_agreement, Ecto.UUID.generate())
    {:ok, verified} = VettingCase.auto_approve_step(with_ca, :staff_attestation, Ecto.UUID.generate())
    {:ok, _} = Vetting.save_case(verified)
  end

  describe "set_responsible_person/3 first capture" do
    test "persists the person and returns :set", %{provider: provider} do
      assert {:ok, :set} = Vetting.set_responsible_person(provider.id, "Jane Smith", "Owner")

      reloaded = reload(provider.id)
      assert reloaded.responsible_person_name == "Jane Smith"
      assert reloaded.responsible_person_role == "Owner"
      assert_no_integration_events_published()
    end
  end

  describe "set_responsible_person/3 with no real change" do
    test "a normalized-equal resubmission is :unchanged and leaves an approved identity approved",
         %{provider: provider} do
      {:ok, :set} = Vetting.set_responsible_person(provider.id, "Jane Smith", "Owner")

      {:ok, case_} = Vetting.get_case_for_provider(provider.id)
      {:ok, approved} = VettingCase.auto_approve_step(case_, :responsible_person_identity, Ecto.UUID.generate())
      {:ok, _} = Vetting.save_case(approved)
      clear_integration_events()

      assert {:ok, :unchanged} = Vetting.set_responsible_person(provider.id, " Jane  Smith ", "Owner")

      assert :approved = step_status(provider.id, :responsible_person_identity)
      assert_no_integration_events_published()
    end
  end

  describe "set_responsible_person/3 with a genuine change" do
    test "resets identity + both agreements, leaves registration/insurance, and unverifies a verified business",
         %{provider: provider} do
      {:ok, :set} = Vetting.set_responsible_person(provider.id, "Jane Smith", "Owner")
      approve_all_business_steps(provider.id)
      admin = AccountsFixtures.user_fixture(%{is_admin: true})
      {:ok, _} = Provider.verify_provider(provider.id, admin.id)
      clear_integration_events()

      assert {:ok, :changed} = Vetting.set_responsible_person(provider.id, "John Doe", "Director")

      assert :not_started = step_status(provider.id, :responsible_person_identity)
      assert :not_started = step_status(provider.id, :community_agreement)
      assert :not_started = step_status(provider.id, :staff_attestation)
      assert :approved = step_status(provider.id, :business_registration)
      assert :approved = step_status(provider.id, :insurance)

      refute reload(provider.id).verified
      assert reload(provider.id).responsible_person_name == "John Doe"
    end

    # Previously asserted that no `:provider_unverified` event was emitted for a
    # never-verified business. Since #1195 that topic has no consumer, so
    # `Outbox.stage/2` drops it either way and the assertion could not fail —
    # it now pins the state the reset actually produces instead.
    test "applies the reset without unverifying a business that was never verified", %{provider: provider} do
      {:ok, :set} = Vetting.set_responsible_person(provider.id, "Jane Smith", "Owner")

      assert {:ok, :changed} = Vetting.set_responsible_person(provider.id, "John Doe", "Director")

      refute reload(provider.id).verified
      assert reload(provider.id).verified_at == nil
      assert reload(provider.id).responsible_person_name == "John Doe"
      assert :not_started = step_status(provider.id, :responsible_person_identity)
    end
  end

  describe "start_responsible_person_verification/4" do
    setup do
      Req.Test.stub(StripeIdentity, fn conn ->
        Req.Test.json(conn, %{
          "id" => "vs_123",
          "url" => "https://verify.stripe.com/start/vs_123",
          "status" => "requires_input"
        })
      end)

      :ok
    end

    test "sets the person, starts the session, and returns the redirect url + change outcome",
         %{provider: provider} do
      assert {:ok, %{redirect_url: "https://verify.stripe.com/start/vs_123", change: :set}} =
               Provider.start_responsible_person_verification(provider.id, "Jane Smith", "Owner", @return_url)

      assert reload(provider.id).responsible_person_name == "Jane Smith"
      assert :submitted = step_status(provider.id, :responsible_person_identity)
      assert {:ok, %{stripe_session_id: "vs_123"}} = Provider.get_latest_identity_verification(provider.id)
    end

    test "surfaces change: :changed when the responsible person genuinely changed", %{provider: provider} do
      {:ok, :set} = Vetting.set_responsible_person(provider.id, "Jane Smith", "Owner")

      assert {:ok, %{change: :changed}} =
               Provider.start_responsible_person_verification(provider.id, "John Doe", "Director", @return_url)

      assert :submitted = step_status(provider.id, :responsible_person_identity)
    end
  end

  describe "create_identity_verification_session/2 business gate (ADR-0010)" do
    setup do
      Req.Test.stub(StripeIdentity, fn conn ->
        Req.Test.json(conn, %{
          "id" => "vs_gate",
          "url" => "https://verify.stripe.com/start/vs_gate",
          "status" => "requires_input"
        })
      end)

      :ok
    end

    test "rejects a business with no responsible person, minting no session or record",
         %{provider: provider} do
      # The direct "start_identity_verification" bypass: no set_responsible_person first.
      assert {:error, :responsible_person_required} =
               Provider.create_identity_verification_session(provider.id, @return_url)

      # Fails closed BEFORE Stripe — no orphan IdentityVerification, step untouched.
      assert {:error, :not_found} = Provider.get_latest_identity_verification(provider.id)
      assert :not_started = step_status(provider.id, :responsible_person_identity)
    end

    test "starts once the responsible person is captured", %{provider: provider} do
      {:ok, :set} = Vetting.set_responsible_person(provider.id, "Jane Smith", "Owner")

      assert {:ok, %{redirect_url: "https://verify.stripe.com/start/vs_gate"}} =
               Provider.create_identity_verification_session(provider.id, @return_url)

      assert :submitted = step_status(provider.id, :responsible_person_identity)
    end

    test "an individual needs no responsible person", %{} do
      individual = ProviderFixtures.provider_profile_fixture(entity_type: "individual")

      assert {:ok, %{redirect_url: "https://verify.stripe.com/start/vs_gate"}} =
               Provider.create_identity_verification_session(individual.id, @return_url)

      assert :submitted = step_status(individual.id, :identity)
    end
  end
end
