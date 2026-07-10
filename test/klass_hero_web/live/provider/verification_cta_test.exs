defmodule KlassHeroWeb.Provider.VerificationCtaTest do
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias KlassHero.Provider.Vetting
  alias KlassHero.Provider.VettingCase
  alias KlassHero.ProviderFixtures

  setup :register_and_log_in_provider

  describe "overview identity CTA" do
    test "shows the verify-identity banner when the identity step is not approved", %{conn: conn, provider: provider} do
      ProviderFixtures.vetting_case_fixture(provider_id: provider.id, entity_type: :individual)

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

      assert has_element?(view, "#identity-verify-cta")
    end

    test "hides the banner once the identity step is approved", %{conn: conn, provider: provider} do
      case_ = ProviderFixtures.vetting_case_fixture(provider_id: provider.id, entity_type: :individual)
      key = VettingCase.step_key_for_identity(case_)
      {:ok, approved} = VettingCase.auto_approve_step(case_, key, nil)
      {:ok, _} = Vetting.save_case(approved)

      {:ok, view, _html} = live(conn, ~p"/provider/dashboard")

      refute has_element?(view, "#identity-verify-cta")
    end
  end
end
