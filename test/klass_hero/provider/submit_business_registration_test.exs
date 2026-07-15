defmodule KlassHero.Provider.SubmitBusinessRegistrationTest do
  @moduledoc """
  The `submit_business_registration/2` command (B2, issue #956): captures the three structured
  registration facts on the provider row AND inserts the registration document in one transaction.
  Unlike B1, registration is a fact about the entity — it carries no `requires` edge and never
  resets vetting (ADR-0010): submitting must not touch the identity step or unverify the business.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.EventTestHelper

  alias KlassHero.AccountsFixtures
  alias KlassHero.Provider
  alias KlassHero.Provider.Vetting
  alias KlassHero.Provider.VettingCase
  alias KlassHero.ProviderFixtures

  @valid_attrs %{
    legal_business_name: "Acme Kids GmbH",
    registration_number: "HRB 12345",
    registration_country: "DE",
    file_binary: "pdf-bytes",
    original_filename: "registration.pdf",
    content_type: "application/pdf"
  }

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

  defp docs(provider_id) do
    {:ok, docs} = Provider.get_provider_verification_documents(provider_id)
    docs
  end

  defp step_status(provider_id, key) do
    {:ok, case_} = Vetting.get_case_for_provider(provider_id)
    Enum.find(case_.steps, &(&1.key == key)).status
  end

  describe "submit_business_registration/2 with valid input" do
    test "persists the three provider columns and inserts a pending registration document",
         %{provider: provider} do
      assert {:ok, doc} = Provider.submit_business_registration(provider.id, @valid_attrs)

      assert doc.document_type == :business_registration
      assert doc.status == :pending

      reloaded = reload(provider.id)
      assert reloaded.legal_business_name == "Acme Kids GmbH"
      assert reloaded.registration_number == "HRB 12345"
      assert reloaded.registration_country == "DE"

      assert [%{id: doc_id}] = docs(provider.id)
      assert doc_id == doc.id
    end
  end

  describe "submit_business_registration/2 with invalid input" do
    test "an invalid country rolls back — no document is inserted", %{provider: provider} do
      attrs = %{@valid_attrs | registration_country: "US"}

      assert {:error, %Ecto.Changeset{}} = Provider.submit_business_registration(provider.id, attrs)

      assert docs(provider.id) == []
      assert reload(provider.id).legal_business_name == nil
    end

    test "returns :not_found for an unknown provider" do
      assert {:error, :not_found} =
               Provider.submit_business_registration(Ecto.UUID.generate(), @valid_attrs)
    end
  end

  describe "submit_business_registration/2 never resets vetting (anti-B1)" do
    test "leaves the identity step approved and the business verified", %{provider: provider} do
      {:ok, :set} = Vetting.set_responsible_person(provider.id, "Jane Smith", "Owner")
      {:ok, case_} = Vetting.get_case_for_provider(provider.id)
      {:ok, approved} = VettingCase.auto_approve_step(case_, :responsible_person_identity, Ecto.UUID.generate())
      {:ok, _} = Vetting.save_case(approved)

      admin = AccountsFixtures.user_fixture(%{is_admin: true})
      {:ok, _} = Provider.verify_provider(provider.id, admin.id)
      clear_integration_events()

      assert {:ok, _doc} = Provider.submit_business_registration(provider.id, @valid_attrs)

      assert :approved = step_status(provider.id, :responsible_person_identity)
      assert reload(provider.id).verified
      assert_no_integration_events_published()
    end
  end
end
