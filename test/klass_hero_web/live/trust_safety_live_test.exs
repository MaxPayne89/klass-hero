defmodule KlassHeroWeb.TrustSafetyLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "TrustSafetyLive" do
    test "renders trust and safety hero with yellow Safety highlight", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/trust-safety")

      assert has_element?(view, "#mk-trust-hero")
      # H1 splits the title into "Trust &" and a yellow-highlighted "Safety" span.
      assert has_element?(view, "#mk-trust-hero h1", "Trust &")
      assert has_element?(view, "#mk-trust-hero h1 span.bg-hero-yellow-500", "Safety")
    end

    test "displays commitment + vetted card section", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/trust-safety")

      assert has_element?(view, "#mk-trust-commitment")
      assert html =~ "Our commitment to child safety"
      assert html =~ "Protect children and families"
      assert html =~ "Every Hero, carefully reviewed."

      # Stats row: 100% / 6-step / Reporting
      assert html =~ "100%"
      assert html =~ "6-step"
      assert html =~ "Reporting"
    end

    test "displays all six verification steps with numbered badges", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/trust-safety")

      assert has_element?(view, "#mk-trust-verification")
      assert html =~ "Six checks. No shortcuts."
      assert html =~ "Identity &amp; Age Verification"
      assert html =~ "Experience Validation"
      assert html =~ "Extended Background Checks"
      assert html =~ "Video Screening"
      assert html =~ "Child Safeguarding Training"
      assert html =~ "Community Standards Agreement"
    end

    test "displays accountability dark slab", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/trust-safety")

      assert has_element?(view, "#mk-trust-accountability")
      assert html =~ "Quality &amp; accountability"
      assert html =~ "may be suspended or removed"
    end

    test "displays CTA section with Contact link and tagline", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/trust-safety")

      assert has_element?(view, "#mk-trust-cta")
      assert html =~ "Have questions?"
      assert html =~ ~s(href="/contact")
      assert html =~ "Trust is earned. Safety is non-negotiable."
      assert html =~ "And at Klass Hero, both come standard."
    end

    test "renders under :marketing chrome (sticky header + dark footer)", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/trust-safety")

      # mk_header sticky nav
      assert has_element?(view, "header.sticky nav a", "Programs")
      # Trust nav item is highlighted as active
      assert has_element?(
               view,
               "header.sticky nav a.text-\\[var\\(--fg-link\\)\\]",
               "Trust & Safety"
             )

      # mk_footer legal links
      assert html =~ "Privacy"
      assert html =~ "Terms"
    end

    test "page uses mobile-first responsive design", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/trust-safety")

      assert html =~ "md:grid-cols-2"
      assert html =~ "lg:grid-cols-3"
    end
  end
end
