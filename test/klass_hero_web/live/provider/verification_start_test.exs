defmodule KlassHeroWeb.Provider.VerificationStartTest do
  # async: false — exercises the StripeIdentity client via the global Req.Test transport.
  use KlassHeroWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias KlassHero.Provider.StripeIdentity
  alias KlassHero.ProviderFixtures

  setup :register_and_log_in_provider

  describe "start identity verification" do
    test "redirects to the Stripe-hosted session url", %{conn: conn, provider: provider} do
      # Factory providers have no vetting case; the command needs one with an identity step.
      ProviderFixtures.vetting_case_fixture(provider_id: provider.id, entity_type: :individual)

      Req.Test.stub(StripeIdentity, fn req_conn ->
        Req.Test.json(req_conn, %{
          "id" => "vs_live",
          "url" => "https://verify.stripe.com/start/vs_live",
          "status" => "requires_input"
        })
      end)

      {:ok, view, _html} = live(conn, ~p"/provider/verification")
      Req.Test.allow(StripeIdentity, self(), view.pid)

      assert {:error, {:redirect, %{to: "https://verify.stripe.com/start/vs_live"}}} =
               view |> element("#identity-verify-start") |> render_click()
    end
  end
end
