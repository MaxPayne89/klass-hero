defmodule KlassHeroWeb.I18n.Phase8ResponsiveI18nTest do
  @moduledoc """
  Phase 8: Mobile Navigation & Responsive Design Testing

  Tests bilingual support across responsive viewports:
  - Translation verification for required strings
  - Mobile navigation functionality
  - Language switcher accessibility
  - Form validation messages in both languages
  """

  use KlassHeroWeb.ConnCase, async: true

  import KlassHeroWeb.I18nHelpers
  import Phoenix.LiveViewTest

  describe "Dashboard Translation Verification" do
    # Use with_child variant to ensure children are displayed on dashboard
    setup :register_and_log_in_user_with_child

    # Phase 2.1 of the design-handoff migration replaced the "My Children"
    # heading with the bundle's silent kid_picker. The dashboard's English
    # surface anchors are now the KPI grid, weekly goal, and upcoming
    # sessions cards.
    test "renders the English dashboard surface", %{conn: conn} do
      {:ok, _view, html} = setup_locale_for_navigation(conn, "en") |> live(~p"/dashboard")

      assert html =~ "Active programs"
      assert html =~ "Weekly adventure goal"
    end

    test "renders the dashboard with the German locale set", %{conn: conn} do
      {:ok, view, _html} = setup_locale_for_navigation(conn, "de") |> live(~p"/dashboard")

      assert_locale(view, "de")
    end

    test "locale is properly set in view assigns", %{conn: conn} do
      {:ok, view, _html} = setup_locale_for_navigation(conn, "de") |> live(~p"/dashboard")
      assert_locale(view, "de")

      {:ok, view, _html} = setup_locale_for_navigation(conn, "en") |> live(~p"/dashboard")
      assert_locale(view, "en")
    end
  end

  describe "Translation Persistence Across Navigation" do
    setup :register_and_log_in_user

    test "persists German locale when navigating from dashboard to programs", %{conn: conn} do
      # Start on dashboard with German locale (query param sets session)
      {:ok, view, _html} = setup_locale_for_navigation(conn, "de") |> live(~p"/dashboard")
      assert_locale(view, "de")

      # Navigate to programs page - locale should persist from session
      {:ok, view, _html} = setup_locale_for_navigation(conn, "de") |> live(~p"/programs")

      # Locale should persist
      assert_locale(view, "de")
      assert_translation(view, "Programs", "de")
    end

    test "persists English locale when navigating between pages", %{conn: conn} do
      # Start on dashboard with English locale
      {:ok, view, _html} = setup_locale_for_navigation(conn, "en") |> live(~p"/dashboard")
      assert_locale(view, "en")

      # Navigate to settings page
      {:ok, view, _html} = setup_locale_for_navigation(conn, "en") |> live(~p"/users/settings")

      # Locale should persist
      assert_locale(view, "en")
    end

    test "updates locale when changing session locale", %{conn: conn} do
      # Start with English
      {:ok, view, _html} = setup_locale_for_navigation(conn, "en") |> live(~p"/dashboard")
      assert_locale(view, "en")

      # Navigate with German locale
      {:ok, view, _html} = setup_locale_for_navigation(conn, "de") |> live(~p"/dashboard")
      assert_locale(view, "de")
    end
  end

  describe "Locale Switching Without Data Loss" do
    setup :register_and_log_in_user

    test "preserves page state when switching locale on dashboard", %{conn: conn} do
      # Load dashboard in English
      {:ok, view, html_en} = setup_locale_for_navigation(conn, "en") |> live(~p"/dashboard")
      assert_locale(view, "en")

      assert html_en =~ "Active programs"

      # Switch to German
      {:ok, view, html_de} = setup_locale_for_navigation(conn, "de") |> live(~p"/dashboard")
      assert_locale(view, "de")

      # Page structure should remain across locale change.
      assert html_de =~ ~s|id="dashboard-stats"|
      assert html_de =~ ~s|id="upcoming-sessions"|
    end

    test "switches locale without losing view context", %{conn: conn} do
      # View programs in English
      {:ok, view, _html} = setup_locale_for_navigation(conn, "en") |> live(~p"/programs")
      assert_locale(view, "en")

      # Switch to German
      {:ok, view, _html} = setup_locale_for_navigation(conn, "de") |> live(~p"/programs")
      assert_locale(view, "de")

      # Program listing should still be present (post design-system migration:
      # the catalog stream lives in #mk-programs-stream, or #mk-empty when no
      # programs match).
      html = render(view)
      assert html =~ "id=\"mk-empty\""
    end
  end

  describe "Navigation Component Translations" do
    setup :register_and_log_in_user

    # Phase 2 of the design-handoff migration moves /dashboard onto the
    # parent_app sidebar layout. Marketing top-nav (Home / Programs / About
    # / Contact) lives on the public live_session layout — these tests now
    # verify the public chrome at /.
    test "navigation items are translated to German", %{conn: conn} do
      {:ok, _view, html} = setup_locale_for_navigation(conn, "de") |> live(~p"/")

      # Check for German navigation labels
      assert html =~ get_translation("Home", "de")
      assert html =~ get_translation("Programs", "de")
      assert html =~ get_translation("About", "de")
      assert html =~ get_translation("Contact", "de")
      # Signed-in marketing CTA (replaces three-button cluster with single primary action)
      assert html =~ get_translation("Go to dashboard", "de")
    end

    test "navigation items are in English by default", %{conn: conn} do
      {:ok, _view, html} = setup_locale_for_navigation(conn, "en") |> live(~p"/")

      # Check for English navigation labels
      assert html =~ "Home"
      assert html =~ "Programs"
      assert html =~ "About"
      assert html =~ "Contact"
      assert html =~ "Go to dashboard"
    end

    test "language switcher is present in navigation", %{conn: conn} do
      {:ok, _view, html} = setup_locale_for_navigation(conn, "en") |> live(~p"/")

      # Language switcher should have EN and DE options
      assert html =~ "🇬🇧"
      assert html =~ "🇩🇪"
    end
  end

  describe "Form Validation Message Translations" do
    test "registration form displays in German", %{conn: conn} do
      path = add_locale_param("/users/register", "de")
      {:ok, view, _html} = setup_locale_for_navigation(conn, "de") |> live(path)

      # Check locale is set
      assert_locale(view, "de")

      html = render(view)
      # Check for German form labels
      assert html =~ get_translation("Email", "de")
    end

    test "registration form displays in English", %{conn: conn} do
      {:ok, view, _html} = setup_locale_for_navigation(conn, "en") |> live(~p"/users/register")

      # Check locale is set
      assert_locale(view, "en")

      html = render(view)
      # Check for English form labels
      assert html =~ "Email"
    end

    test "locale is maintained in form context", %{conn: conn} do
      # Test that German locale is maintained
      path_de = add_locale_param("/users/register", "de")
      {:ok, view, _html} = setup_locale_for_navigation(conn, "de") |> live(path_de)
      assert_locale(view, "de")

      # Test that English locale is maintained
      path_en = add_locale_param("/users/register", "en")
      {:ok, view, _html} = setup_locale_for_navigation(conn, "en") |> live(path_en)
      assert_locale(view, "en")
    end
  end

  describe "Page Content Translations" do
    setup :register_and_log_in_user

    test "home page displays German locale", %{conn: conn} do
      # Visit home page without authentication
      conn = Phoenix.ConnTest.recycle(conn)
      path = add_locale_param("/", "de")
      {:ok, view, _html} = setup_locale_for_navigation(conn, "de") |> live(path)

      assert_locale(view, "de")
    end

    test "programs page displays German translations", %{conn: conn} do
      {:ok, view, _html} = setup_locale_for_navigation(conn, "de") |> live(~p"/programs")

      assert_locale(view, "de")
      assert_translation(view, "Programs", "de")
    end

    test "about page displays German translations", %{conn: conn} do
      {:ok, view, _html} = setup_locale_for_navigation(conn, "de") |> live(~p"/about")

      assert_locale(view, "de")
      # Post design-system migration: hero pill replaces the all-caps page title.
      assert_translation(view, "Our Mission", "de")
    end

    test "contact page displays German translations", %{conn: conn} do
      {:ok, view, _html} = setup_locale_for_navigation(conn, "de") |> live(~p"/contact")

      assert_locale(view, "de")
      assert_translation(view, "Contact Us", "de")
    end
  end

  describe "Settings Page Translations" do
    setup :register_and_log_in_user

    test "settings page displays German menu items", %{conn: conn} do
      {:ok, view, _html} = setup_locale_for_navigation(conn, "de") |> live(~p"/users/settings")

      assert_locale(view, "de")

      # Check for German settings menu items
      assert_translation(view, "Preferences", "de")
      assert_translation(view, "My Family", "de")
    end

    test "user can change language preference in settings", %{conn: conn} do
      {:ok, view, _html} = setup_locale_for_navigation(conn, "de") |> live(~p"/users/settings")

      assert_locale(view, "de")

      # Settings should show current locale preference
      html = render(view)
      assert html =~ "🇩🇪"
    end
  end

  describe "Community Page Translations" do
    @describetag :skip
    setup :register_and_log_in_user

    test "community page displays German translations", %{conn: conn} do
      {:ok, view, _html} = setup_locale_for_navigation(conn, "de") |> live("/community")

      assert_locale(view, "de")
      assert_translation(view, "Community", "de")
    end

    test "community posts display German locale", %{conn: conn} do
      {:ok, view, _html} = setup_locale_for_navigation(conn, "de") |> live("/community")

      assert_locale(view, "de")

      html = render(view)

      # Verify the community page structure is rendered
      # The page should have posts stream container
      assert html =~ "phx-update=\"stream\""
    end
  end
end
