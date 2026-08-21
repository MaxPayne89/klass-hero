defmodule KlassHeroWeb.E2E.LoginBrowserTest do
  @moduledoc """
  The real login form, which only a browser can drive.

  `UserLive.Login` renders a mobile and a desktop copy of the same
  `phx-trigger-action` form. `phoenix_test` raises `"Found multiple forms with
  phx-trigger-action."` on more than one, and a `Phoenix.LiveViewTest` test has to
  pick a copy by hand and call `follow_trigger_action/2` — neither answers the
  question this asks: does a person clicking the button that is actually visible
  end up logged in?

  The trigger is a client-side POST issued after the LiveView sets
  `trigger_submit=true`, so the round-trip is real JavaScript.
  """

  use KlassHeroWeb.E2ECase

  describe "password login" do
    test "the visible form logs the user in and lands them on their dashboard", %{
      sandbox_metadata: metadata
    } do
      user = user_fixture(%{intended_roles: [:parent]}) |> set_password()
      insert(:parent_profile_schema, identity_id: user.id)

      session = new_session(metadata) |> log_in(user)

      assert String.ends_with?(Wallaby.Browser.current_url(session), "/dashboard")
      assert_has(session, Query.css("body", text: user.email, count: :any))
    end

    test "a wrong password keeps the user on the login page", %{sandbox_metadata: metadata} do
      user = user_fixture() |> set_password()

      session =
        new_session(metadata)
        |> visit("/users/log-in")
        |> fill_in(Query.css("#login_form_password_email"), with: user.email)
        |> fill_in(Query.css("#login_form_password_password"), with: "not-the-password")
        |> click(Query.css("#login_form_password button[name='user[remember_me]']"))

      assert_has(session, Query.css("[role='alert']", text: "Invalid email or password"))
      assert Wallaby.Browser.current_url(session) =~ "/users/log-in"
    end
  end
end
