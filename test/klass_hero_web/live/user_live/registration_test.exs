defmodule KlassHeroWeb.UserLive.RegistrationTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.AccountsFixtures
  import Phoenix.LiveViewTest

  alias KlassHero.Accounts.User

  describe "Registration page" do
    test "renders registration page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/register")

      assert html =~ "Create your"
      assert html =~ "Log in"
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/register")
        |> follow_redirect(conn, ~p"/dashboard")

      assert {:ok, _conn} = result
    end

    test "renders errors for invalid data", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      result =
        lv
        |> element("#registration_form")
        |> render_change(user: %{"email" => "with spaces"})

      assert result =~ "Create an account"
      assert result =~ "must have the @ sign and no spaces"
    end
  end

  describe "register user" do
    test "creates account but does not log in", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()
      name = unique_user_name()
      form = form(lv, "#registration_form", user: %{email: email, name: name})

      {:ok, _lv, html} =
        render_submit(form)
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~
               ~r/An email was sent to .*, please access it to confirm your account/
    end

    test "renders errors for duplicated email", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      user = user_fixture(%{email: "test@email.com"})

      result =
        lv
        |> form("#registration_form",
          user: %{"email" => user.email}
        )
        |> render_submit()

      assert result =~ "has already been taken"
    end
  end

  describe "registration navigation" do
    test "redirects to login page when the Log in button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      {:ok, _login_live, login_html} =
        lv
        |> element("main a", "Log in")
        |> render_click()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert login_html =~ "Welcome"
    end
  end

  describe "role selection" do
    test "renders role selection checkboxes with descriptions", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/register")

      assert html =~ "I want to..."
      assert html =~ "Enroll children in programs"
      assert html =~ "Offer programs and services"
      assert html =~ ~s(value="parent")
      assert html =~ ~s(value="provider")
    end

    test "parent role is pre-selected by default", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/register")

      # Parent checkbox should be checked by default
      assert html =~ ~r/value="parent"[^>]*checked/
    end

    test "creates account with both roles selected", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()
      name = unique_user_name()

      {:ok, _lv, html} =
        lv
        |> form("#registration_form",
          user: %{email: email, name: name, intended_roles: [:parent, :provider]}
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ ~r/An email was sent to .*, please access it to confirm your account/

      # Verify user was created with both roles
      user = KlassHero.Repo.get_by!(User, email: email)
      assert :parent in user.intended_roles
      assert :provider in user.intended_roles
    end

    test "creates account with only provider role", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()
      name = unique_user_name()

      {:ok, _lv, html} =
        lv
        |> form("#registration_form",
          user: %{email: email, name: name, intended_roles: [:provider]}
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ ~r/An email was sent to .*, please access it to confirm your account/

      # Verify user was created with provider role only
      user = KlassHero.Repo.get_by!(User, email: email)
      assert user.intended_roles == [:provider]
    end

    test "defaults to parent role when none selected", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()
      name = unique_user_name()

      # Submit form without specifying roles - should default to parent
      {:ok, _lv, html} =
        lv
        |> form("#registration_form",
          user: %{email: email, name: name}
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ ~r/An email was sent to .*, please access it to confirm your account/

      # Verify user was created with default parent role
      user = KlassHero.Repo.get_by!(User, email: email)
      assert user.intended_roles == [:parent]
    end
  end
end
