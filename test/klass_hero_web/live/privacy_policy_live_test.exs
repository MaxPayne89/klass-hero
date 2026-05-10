defmodule KlassHeroWeb.PrivacyPolicyLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "Privacy Policy page" do
    test "renders privacy policy page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/privacy")

      assert html =~ "Privacy Policy"
      assert html =~ "Your privacy matters to us"
    end

    test "displays last updated date", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/privacy")

      assert html =~ "Last Updated"
      assert html =~ "February 1, 2026"
    end

    test "includes table of contents", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/privacy")

      assert html =~ "Table of Contents"
      assert has_element?(view, "a[href='#introduction']")
      assert has_element?(view, "a[href='#information-collected']")
      assert has_element?(view, "a[href='#how-we-use']")
      assert has_element?(view, "a[href='#data-sharing']")
      assert has_element?(view, "a[href='#user-rights']")
      assert has_element?(view, "a[href='#data-security']")
      assert has_element?(view, "a[href='#children-privacy']")
      assert has_element?(view, "a[href='#cookies']")
    end

    test "renders all privacy policy sections", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/privacy")

      # Check for key section titles
      assert html =~ "Introduction"
      assert html =~ "Information We Collect"
      assert html =~ "How We Use Your Information"
      assert html =~ "Data Sharing"
      assert html =~ "Your Privacy Rights"
      assert html =~ "Data Security"
      assert html =~ "Children&#39;s Privacy"
      assert html =~ "Cookies &amp; Tracking"
      assert html =~ "Data Retention"
      assert html =~ "Changes to This Policy"
      assert html =~ "Contact Us"
    end

    test "mentions GDPR compliance", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/privacy")

      assert html =~ "GDPR"
      assert html =~ "data protection"
    end

    test "mentions user rights (export, deletion)", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/privacy")

      assert html =~ "Export My Data"
      assert html =~ "deletion"
      assert html =~ "Right to Access"
      assert html =~ "Right to Deletion"
    end

    test "mentions payment methods", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/privacy")

      assert html =~ "credit card"
      assert html =~ "direct transfer"
      assert html =~ "cash"
    end

    test "clarifies no third-party tracking", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/privacy")

      assert html =~ "essential" or html =~ "session cookies"
      assert html =~ "never sell"
    end

    test "includes contact information", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/privacy")

      assert html =~ "info@mail.klasshero.com"
      assert html =~ "Contact Us"
      assert has_element?(view, ~s|a[href="mailto:info@mail.klasshero.com"]|)
    end

    test "accessible without authentication", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/privacy")

      assert html =~ "Privacy Policy"
      refute html =~ "You must log in"
    end

    test "renders under :marketing chrome", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/privacy")

      assert has_element?(view, "header.sticky")
      # mk_footer presence — assert structural footer link, label-translation-independent
      assert has_element?(view, "footer a[href='/terms']")
    end

    test "includes contact CTA section", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/privacy")

      assert html =~ "Questions About Privacy?"
      assert has_element?(view, "a[href='/contact']")
    end

    test "sets correct page title", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/privacy")

      assert page_title(view) =~ "Privacy Policy"
    end

    test "includes required children's data protection statement", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/privacy")

      assert html =~ "data minimization"
      assert html =~ "explicit parental consent"
      assert html =~ "safety and participation purposes"
    end

    test "describes consent-gated provider data sharing", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/privacy")

      assert html =~ "consent"
      assert html =~ "Behavioral"
    end
  end
end
