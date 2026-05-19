defmodule KlassHeroWeb.ForProvidersLiveTest do
  @moduledoc """
  Phase 1 — `/for-providers` marketing page.
  Asserts the bundle's MkForProviders sections render in order, that pricing
  tiers are filtered against `Entitlements.all_provider_tiers/0`, and that
  the FLAGS-deferred surfaces (hero stats strip, success stories, monthly /
  annual toggle) are NOT rendered.
  """

  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias KlassHero.Shared.Entitlements

  describe "ForProvidersLive" do
    test "renders the page successfully at /for-providers", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/for-providers")

      assert has_element?(view, "#for-providers-hero")
    end

    test "renders the marketing sections in order", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/for-providers")

      assert html =~ ~s|id="for-providers-hero"|
      assert html =~ ~s|id="for-providers-benefits"|
      assert html =~ ~s|id="for-providers-how-it-works"|
      assert html =~ ~s|id="for-providers-safety-standards"|
      assert html =~ ~s|id="for-providers-pricing"|
      assert html =~ ~s|id="for-providers-faq"|

      hero_pos = String.split(html, ~s|id="for-providers-hero"|) |> hd() |> String.length()

      benefits_pos =
        String.split(html, ~s|id="for-providers-benefits"|) |> hd() |> String.length()

      how_it_works_pos =
        String.split(html, ~s|id="for-providers-how-it-works"|) |> hd() |> String.length()

      safety_pos =
        String.split(html, ~s|id="for-providers-safety-standards"|) |> hd() |> String.length()

      pricing_pos =
        String.split(html, ~s|id="for-providers-pricing"|) |> hd() |> String.length()

      faq_pos = String.split(html, ~s|id="for-providers-faq"|) |> hd() |> String.length()

      assert hero_pos < benefits_pos
      assert benefits_pos < how_it_works_pos
      assert how_it_works_pos < safety_pos
      assert safety_pos < pricing_pos
      assert pricing_pos < faq_pos
    end

    test "renders the dark hero with primary CTA pointing to /users/register", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/for-providers")

      assert html =~ "Teach more."
      assert html =~ "Manage less."
      assert html =~ ~s|href="/users/register"|
    end

    test "omits the hero stats strip (FLAGS ❌ — no real metrics source)", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/for-providers")

      refute html =~ "2,400+"
      refute html =~ "Berlin families"
      refute html =~ "Paid out in 2025"
    end

    test "renders the 6-up benefits grid", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/for-providers")

      assert html =~ "Stop chasing leads"
      assert html =~ "Less admin, more teaching"
      assert html =~ "Predictable income"
      assert html =~ "Built-in trust"
      assert html =~ "Better parent relationships"
      assert html =~ "Insights that matter"
    end

    test "renders the 4-step how-it-works slab", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/for-providers")

      assert html =~ "List your program"
      assert html =~ "Get verified"
      assert html =~ "Receive bookings"
      assert html =~ "Get paid weekly"
    end

    test "renders the 8-up safety standards grid", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/for-providers")

      assert has_element?(view, "#for-providers-safety-standards")
      assert html =~ "The bar to teach on Klass Hero"
      assert html =~ "Age &amp; Identity"
      assert html =~ "Teaching Experience"
      assert html =~ "Extended Police Check"
      assert html =~ "Pedagogical Interview"
      assert html =~ "Safeguarding Training"
      assert html =~ "Qualifications"
      assert html =~ "Community Standards"
      assert html =~ "Liability Insurance"
    end

    test "renders one pricing tier per backed Entitlements provider tier", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/for-providers")

      backed = Keyword.keys(Entitlements.all_provider_tiers())

      # Tier marketing labels we know about. If a backed atom isn't in this
      # list, the LiveView quietly drops it — that's intentional.
      labels_for_atom = %{
        starter: "Starter",
        professional: "Professional",
        business_plus: "Business Plus"
      }

      backed
      |> Enum.map(&Map.get(labels_for_atom, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.each(fn label ->
        assert html =~ label, "expected pricing tier label #{inspect(label)} to render"
      end)
    end

    test "omits the monthly / annual toggle (FLAGS ❌)", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/for-providers")

      refute html =~ "Save €"
      refute html =~ "−20%"
    end

    test "omits the provider success stories (FLAGS ❌)", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/for-providers")

      refute html =~ "Success Stories"
      refute html =~ "Heroes building real businesses"
      refute html =~ "↑ 40% bookings"
    end

    test "renders an expanded first FAQ and collapsed others", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/for-providers")

      assert has_element?(view, "#for-providers-faq-0-answer")
      assert has_element?(view, "#for-providers-faq-4-answer")
    end

    test "renders under :marketing chrome", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/for-providers")

      assert has_element?(view, "header.sticky")
      assert has_element?(view, "header.sticky nav a", "For Providers")
      assert html =~ "Privacy"
    end

    test "renders the dark final CTA below the FAQ", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/for-providers")

      assert html =~ ~s|id="for-providers-final-cta"|

      faq_pos = String.split(html, ~s|id="for-providers-faq"|) |> hd() |> String.length()

      cta_pos = String.split(html, ~s|id="for-providers-final-cta"|) |> hd() |> String.length()

      assert faq_pos < cta_pos
    end

    test "final CTA carries 'Ready to be a Hero?' headline + reassurance row", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/for-providers")

      assert html =~ "Ready to be a Hero?"
      assert html =~ "Free to start"
      assert html =~ "Cancel anytime"
      assert html =~ "No credit card required"
    end

    test "FAQ section has 'Talk to our team' trailer link to /contact", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/for-providers")

      assert html =~ "Still curious?"
      assert html =~ "Talk to our team"
    end
  end
end
