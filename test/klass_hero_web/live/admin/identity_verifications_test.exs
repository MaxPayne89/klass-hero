defmodule KlassHeroWeb.Admin.IdentityVerificationsTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.Factory
  import Phoenix.LiveViewTest

  alias KlassHero.ProviderFixtures

  describe "admin identity verifications section" do
    setup :register_and_log_in_admin

    test "lists a provider's identity verification with status, read-only", %{conn: conn} do
      provider = insert(:provider_profile_schema, business_name: "Acme Sports")

      iv =
        ProviderFixtures.identity_verification_fixture(
          provider_id: provider.id,
          status: :verified,
          outcome: :fail,
          failure_reason: "under_18"
        )

      {:ok, view, _html} = live(conn, ~p"/admin/verifications")

      assert has_element?(view, "#identity-verification-#{iv.id}")
      assert has_element?(view, "#identity-verifications-section", "Acme Sports")
      # Read-only: no approve/reject controls on identity rows.
      refute has_element?(view, "#identity-verification-#{iv.id} button")
    end
  end
end
