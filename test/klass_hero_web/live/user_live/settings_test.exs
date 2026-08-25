defmodule KlassHeroWeb.UserLive.SettingsTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.AccountsFixtures
  import Phoenix.LiveViewTest

  alias KlassHero.Accounts

  describe "Settings page" do
    test "renders settings page", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings")

      assert html =~ "Change Email"
      assert html =~ "Save Password"
    end

    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/users/settings")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "redirects if user is not in sudo mode", %{conn: conn} do
      {:ok, conn} =
        conn
        |> log_in_user(user_fixture(),
          token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)
        )
        |> live(~p"/users/settings")
        |> follow_redirect(conn, ~p"/users/log-in")

      assert conn.resp_body =~ "You must re-authenticate to access this page."
    end
  end

  describe "update email form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "updates the user email", %{conn: conn, user: user} do
      new_email = unique_user_email()

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#email_form", %{
          "user" => %{"email" => new_email}
        })
        |> render_submit()

      assert result =~ "A link to confirm your email"
      assert Accounts.get_user_by_email(user.email)
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> element("#email_form")
        |> render_change(%{
          "action" => "update_email",
          "user" => %{"email" => "with spaces"}
        })

      assert result =~ "Change Email"
      assert result =~ "must have the @ sign and no spaces"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#email_form", %{
          "user" => %{"email" => user.email}
        })
        |> render_submit()

      assert result =~ "Change Email"
      assert result =~ "did not change"
    end
  end

  describe "update password form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    # Asserts the flash on the conn returned by follow_trigger_action, not on a socket.
    @tag :plug_test
    test "updates the user password", %{conn: conn, user: user} do
      new_password = valid_user_password()

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      form =
        form(lv, "#password_form", %{
          "user" => %{
            "email" => user.email,
            "password" => new_password,
            "password_confirmation" => new_password
          }
        })

      render_submit(form)

      new_password_conn = follow_trigger_action(form, conn)

      assert redirected_to(new_password_conn) == ~p"/users/settings"

      assert get_session(new_password_conn, :user_token) != get_session(conn, :user_token)

      assert Phoenix.Flash.get(new_password_conn.assigns.flash, :info) =~
               "Password updated successfully"

      assert Accounts.get_user_by_email_and_password(user.email, new_password)
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> element("#password_form")
        |> render_change(%{
          "user" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })

      assert result =~ "Save Password"
      assert result =~ "should be at least 12 character(s)"
      assert result =~ "does not match password"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#password_form", %{
          "user" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })
        |> render_submit()

      assert result =~ "Save Password"
      assert result =~ "should be at least 12 character(s)"
      assert result =~ "does not match password"
    end
  end

  describe "delete account form" do
    setup %{conn: conn} do
      user = user_fixture() |> set_password()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "renders delete account section", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/settings")

      assert html =~ "Delete Account"
      assert html =~ "Delete My Account"
      assert html =~ "Enter your password to confirm"
    end

    test "deletes account with valid password", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#delete_account_form", %{
          "delete" => %{"password" => valid_user_password()}
        })
        |> render_submit()

      assert {:error, {:redirect, %{to: "/"}}} = result

      refute Accounts.get_user_by_email(user.email)

      anonymized_user = Accounts.get_user!(user.id)
      assert anonymized_user.email == "deleted_#{user.id}@anonymized.local"
      assert anonymized_user.name == "Deleted User"
    end

    test "shows error with invalid password", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#delete_account_form", %{
          "delete" => %{"password" => "wrongpassword"}
        })
        |> render_submit()

      assert result =~ "Invalid password"
      assert Accounts.get_user_by_email(user.email)
    end
  end

  describe "my family section" do
    test "renders family section with no children", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings")

      assert html =~ "My Family"
      assert html =~ "Children Profiles"
      assert html =~ "/settings/children"
      assert html =~ "No children yet"
    end

    test "renders family section with child summary", %{conn: conn} do
      %{conn: conn} = register_and_log_in_user_with_child(%{conn: conn})

      {:ok, _lv, html} = live(conn, ~p"/users/settings")

      assert html =~ "My Family"
      assert html =~ "Emma"
      assert html =~ "/settings/children"
    end
  end

  describe "confirm email" do
    setup %{conn: conn} do
      user = user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{conn: log_in_user(conn, user), token: token, email: email, user: user}
    end

    test "updates the user email once", %{conn: conn, user: user, token: token, email: email} do
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/#{token}")

      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"info" => message} = flash
      assert message == "Email changed successfully."
      refute Accounts.get_user_by_email(user.email)
      assert Accounts.get_user_by_email(email)

      # use confirm token again
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/#{token}")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"error" => message} = flash
      assert message == "Email change link is invalid or it has expired."
    end

    test "does not update email with invalid token", %{conn: conn, user: user} do
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/oops")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"error" => message} = flash
      assert message == "Email change link is invalid or it has expired."
      assert Accounts.get_user_by_email(user.email)
    end

    test "redirects if user is not logged in", %{token: token} do
      conn = build_conn()
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/#{token}")
      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => message} = flash
      assert message == "You must log in to access this page."
    end
  end

  describe "language preference" do
    setup %{conn: conn} do
      user = user_fixture()

      %{conn: log_in_user(conn, user), user: user}
    end

    # The radios are generated from Locale.supported/0, so a locale added to the
    # config without display metadata renders a blank, unlabelled option rather
    # than not rendering at all — assert the label and flag are actually there.
    test "offers exactly one labelled option per supported locale", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      for locale <- KlassHeroWeb.Locale.supported() do
        assert has_element?(lv, "#locale-option-#{locale}"),
               "no radio rendered for supported locale #{locale}"

        assert has_element?(lv, "#locale-option-#{locale} input[value='#{locale}']")

        assert lv
               |> element("#locale-option-#{locale}")
               |> render() =~ KlassHeroWeb.Locale.label(locale)
      end
    end

    test "hands the change to the controller that can write the session", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      assert {:error, {:redirect, %{to: to}}} =
               lv |> form("#locale_form", user: %{locale: "de"}) |> render_change()

      assert to == "/locale/de?return_to=/users/settings"
    end

    # The bug in #1161: the LiveView wrote the database and its own socket, but
    # SetLocale reads the session first and a LiveView cannot write one. The
    # choice therefore evaporated on the very next page load.
    test "the chosen language survives a page reload", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      {:error, {:redirect, %{to: to}}} =
        lv |> form("#locale_form", user: %{locale: "de"}) |> render_change()

      conn = get(conn, to)
      assert redirected_to(conn) == "/users/settings"

      reloaded =
        conn
        |> get(~p"/users/settings")
        |> html_response(200)
        |> LazyHTML.from_document()
        |> LazyHTML.query("html")
        |> LazyHTML.attribute("lang")

      assert reloaded == ["de"], "the language reverted on reload — the session was never written"
      assert KlassHero.Repo.reload!(user).locale == "de"
    end
  end
end
