defmodule KlassHeroWeb.Flows.LoginTest do
  @moduledoc """
  Flow test for the login page.

  The *password* login is deliberately absent: `UserLive.Login` renders a mobile and
  a desktop copy of the same `phx-trigger-action` form, and `phoenix_test` raises on
  more than one. That path belongs to the browser tier — see
  `test/e2e/login_browser_test.exs` and ADR-0020.
  """

  use KlassHeroWeb.FlowCase, async: false

  import Ecto.Query

  alias KlassHero.Accounts.UserToken

  describe "user login journey" do
    test "user can log in with magic link", %{conn: conn} do
      user = user_fixture()

      conn
      |> visit(~p"/users/log-in")
      |> assert_has("h1", text: "Welcome")
      |> click_button("Or use magic link")
      |> within("#login_form_magic", fn session ->
        session
        |> fill_in("Email", with: user.email)
        |> click_button("Send magic link")
      end)
      |> assert_has("[role='alert']", text: "If your email is in our system")

      assert KlassHero.Repo.exists?(
               from t in UserToken,
                 where: t.user_id == ^user.id and t.context == "login"
             )
    end

    test "user can toggle to the magic link form", %{conn: conn} do
      conn
      |> visit(~p"/users/log-in")
      |> assert_has("button", text: "Log in and stay logged in")
      |> assert_has("input[type='password']")
      |> click_button("Or use magic link")
      |> assert_has("button", text: "Send magic link")
    end

    # Scoped to the desktop nav because the page renders a mobile copy of the same
    # link. Before this was scoped it was a `do :skip end` body — green while
    # asserting nothing.
    test "the login page offers a route to registration", %{conn: conn} do
      conn
      |> visit(~p"/users/log-in")
      |> assert_has(~s(a[href="#{~p"/users/register"}"]))
    end
  end

  describe "authenticated user experience" do
    test "already logged in user sees reauthentication prompt", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      conn
      |> visit(~p"/users/log-in")
      |> assert_has("p", text: "You need to reauthenticate")
      |> refute_has("a", text: "Register")
      |> assert_has("input[value='#{user.email}']")
    end
  end
end
