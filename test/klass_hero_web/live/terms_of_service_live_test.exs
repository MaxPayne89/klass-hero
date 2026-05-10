defmodule KlassHeroWeb.TermsOfServiceLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "Terms of Service page" do
    test "renders terms of service page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/terms")

      assert html =~ "Terms of Service"
      assert html =~ "Understanding our agreement with you"
    end

    test "displays last updated date", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/terms")

      assert html =~ "Last Updated"
      assert html =~ "December 12, 2025"
    end

    test "includes table of contents", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/terms")

      assert html =~ "Table of Contents"
      assert has_element?(view, "a[href='#agreement']")
      assert has_element?(view, "a[href='#user-accounts']")
      assert has_element?(view, "a[href='#program-enrollment']")
      assert has_element?(view, "a[href='#payment-terms']")
      assert has_element?(view, "a[href='#cancellation-refund']")
      assert has_element?(view, "a[href='#user-conduct']")
    end

    test "renders all terms sections", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/terms")

      # Check for key section titles
      assert html =~ "Agreement to Terms"
      assert html =~ "User Accounts &amp; Registration"
      assert html =~ "Program Enrollment &amp; Bookings"
      assert html =~ "Payment Terms"
      assert html =~ "Cancellation &amp; Refund Policy"
      assert html =~ "User Conduct &amp; Responsibilities"
      assert html =~ "Limitation of Liability"
      assert html =~ "Intellectual Property"
      assert html =~ "Changes to Terms"
      assert html =~ "Account Termination"
      assert html =~ "Dispute Resolution"
      assert html =~ "Contact Information"
    end

    test "mentions account responsibilities", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/terms")

      assert html =~ "18 years old"
      assert html =~ "account credentials"
      assert html =~ "accurate"
    end

    test "mentions payment methods", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/terms")

      assert html =~ "Credit Card"
      assert html =~ "Direct Bank Transfer" or html =~ "direct transfer"
      assert html =~ "Cash"
    end

    test "includes cancellation policy", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/terms")

      assert html =~ "Cancellation"
      assert html =~ "refund"
    end

    test "mentions user conduct expectations", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/terms")

      assert html =~ "respect"
      assert html =~ "safety"
      assert html =~ "Prohibited"
    end

    test "includes liability limitations", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/terms")

      assert html =~ "Limitation of Liability"
      assert html =~ "liable"
    end

    test "includes contact information", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/terms")

      assert html =~ "info@mail.klasshero.com"
      assert html =~ "Contact Information"
    end

    test "accessible without authentication", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/terms")

      assert html =~ "Terms of Service"
      refute html =~ "You must log in"
    end

    test "renders under :marketing chrome", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/terms")

      assert has_element?(view, "header.sticky")
      # mk_footer presence — assert structural footer link, label-translation-independent
      assert has_element?(view, "footer a[href='/privacy']")
    end

    test "includes contact CTA section", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/terms")

      assert html =~ "Questions About These Terms?"
      assert has_element?(view, "a[href='/contact']")
    end

    test "sets correct page title", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/terms")

      assert page_title(view) =~ "Terms of Service"
    end

    test "mentions agreement acknowledgment", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/terms")

      assert html =~ "By using Klass Hero" or html =~ "agree to be bound"
    end
  end
end
