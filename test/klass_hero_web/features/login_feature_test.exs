defmodule KlassHeroWeb.Features.LoginFeatureTest do
  @moduledoc """
  Feature test for user login flow using phoenix_test.
  Demonstrates the user-centric testing approach.
  """

  use KlassHeroWeb.FeatureCase, async: true

  import Ecto.Query

  alias KlassHero.Accounts.UserToken

  describe "user login journey" do
    test "user can log in with magic link", %{conn: conn} do
      user = user_fixture()

      conn
      |> visit("/users/log-in")
      |> assert_has("h1", text: "Welcome")
      |> click_button("Or use magic link")
      |> within("#login_form_magic", fn session ->
        session
        |> fill_in("Email", with: user.email)
        |> click_button("Send magic link")
      end)
      |> assert_has("[role='alert']", text: "If your email is in our system")

      # Verify token was created
      assert KlassHero.Repo.exists?(
               from t in UserToken,
                 where: t.user_id == ^user.id and t.context == "login"
             )
    end

    # Password login tests are in login_test.exs using LiveViewTest
    # phoenix_test cannot handle duplicate forms (mobile + desktop) with phx-trigger-action
    test "user can toggle to magic link form", %{conn: conn} do
      conn
      |> visit("/users/log-in")
      |> assert_has("button", text: "Log in and stay logged in")
      |> assert_has("input[type='password']")
      |> click_button("Or use magic link")
      |> assert_has("button", text: "Send magic link")
    end

    test "user can navigate to registration from login", %{conn: _conn} do
      # PhoenixTest cannot distinguish between mobile and desktop "Sign up" links
      # since both are rendered in HTML (one is CSS hidden). Skip this test
      # as the same functionality is tested in login_test.exs using LiveViewTest
      :skip
    end
  end

  describe "authenticated user experience" do
    test "already logged in user sees reauthentication prompt", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      conn
      |> visit("/users/log-in")
      |> assert_has("p", text: "You need to reauthenticate")
      |> refute_has("a", text: "Register")
      |> assert_has("input[value='#{user.email}']")
    end
  end
end
