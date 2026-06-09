defmodule KlassHeroWeb.UserLive.StaffInvitationTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.AccountsFixtures
  import KlassHero.ProviderFixtures
  import Phoenix.LiveViewTest

  alias KlassHero.Accounts.Scope
  alias KlassHero.Accounts.User

  defp create_staff_with_invitation(opts \\ []) do
    provider = provider_profile_fixture()
    raw_bytes = :crypto.strong_rand_bytes(32)
    raw_token = Base.url_encode64(raw_bytes, padding: false)
    token_hash = :crypto.hash(:sha256, raw_bytes)

    sent_at = Keyword.get(opts, :invitation_sent_at, DateTime.utc_now())
    email = Keyword.get(opts, :email, "invited-#{System.unique_integer([:positive])}@example.com")

    staff =
      staff_member_fixture(%{
        provider_id: provider.id,
        first_name: "Jane",
        last_name: "Doe",
        email: email,
        invitation_status: :sent,
        invitation_token_hash: token_hash,
        invitation_sent_at: sent_at
      })

    {raw_token, staff, provider}
  end

  describe "valid invitation token" do
    test "renders registration form", %{conn: conn} do
      {raw_token, _staff, _provider} = create_staff_with_invitation()

      {:ok, view, _html} = live(conn, ~p"/users/staff-invitation/#{raw_token}")

      assert has_element?(view, "#staff-registration-form")
      assert has_element?(view, "input[name='user[name]']")
      assert has_element?(view, "input[name='user[email]']")
      assert has_element?(view, "input[name='user[password]']")
    end

    test "pre-fills name and email from staff member", %{conn: conn} do
      {raw_token, staff, _provider} = create_staff_with_invitation()

      {:ok, _view, html} = live(conn, ~p"/users/staff-invitation/#{raw_token}")

      assert html =~ staff.email
      assert html =~ "Jane Doe"
    end

    test "email field is readonly", %{conn: conn} do
      {raw_token, _staff, _provider} = create_staff_with_invitation()

      {:ok, view, _html} = live(conn, ~p"/users/staff-invitation/#{raw_token}")

      assert has_element?(view, "input[readonly][name='user[email]']")
    end

    test "renders password field with correct type", %{conn: conn} do
      {raw_token, _staff, _provider} = create_staff_with_invitation()

      {:ok, view, _html} = live(conn, ~p"/users/staff-invitation/#{raw_token}")

      assert has_element?(view, "input[type='password'][name='user[password]']")
    end
  end

  describe "invalid invitation token" do
    test "shows invalid error for unknown token", %{conn: conn} do
      garbage_bytes = :crypto.strong_rand_bytes(32)
      bad_token = Base.url_encode64(garbage_bytes, padding: false)

      {:ok, view, _html} = live(conn, ~p"/users/staff-invitation/#{bad_token}")

      assert render(view) =~ "Invalid Invitation"
      refute has_element?(view, "#staff-registration-form")
    end

    test "shows invalid error for malformed token", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/staff-invitation/not-valid-base64!!!")

      assert render(view) =~ "Invalid Invitation"
      refute has_element?(view, "#staff-registration-form")
    end
  end

  describe "expired invitation token" do
    test "shows expiry message for invitation older than 7 days", %{conn: conn} do
      eight_days_ago = DateTime.add(DateTime.utc_now(), -8, :day)

      {raw_token, _staff, _provider} =
        create_staff_with_invitation(invitation_sent_at: eight_days_ago)

      {:ok, view, _html} = live(conn, ~p"/users/staff-invitation/#{raw_token}")

      assert render(view) =~ "Invitation Expired"
      refute has_element?(view, "#staff-registration-form")
    end

    test "shows expiry at exactly 7-day boundary", %{conn: conn} do
      exactly_7_days_ago = DateTime.add(DateTime.utc_now(), -7, :day)

      {raw_token, _staff, _provider} =
        create_staff_with_invitation(invitation_sent_at: exactly_7_days_ago)

      {:ok, view, _html} = live(conn, ~p"/users/staff-invitation/#{raw_token}")

      assert render(view) =~ "Invitation Expired"
      refute has_element?(view, "#staff-registration-form")
    end

    test "invitation at 6 days 23 hours is still valid", %{conn: conn} do
      almost_7_days_ago = DateTime.add(DateTime.utc_now(), -(7 * 24 * 60 - 60), :minute)

      {raw_token, _staff, _provider} =
        create_staff_with_invitation(invitation_sent_at: almost_7_days_ago)

      {:ok, view, _html} = live(conn, ~p"/users/staff-invitation/#{raw_token}")

      assert has_element?(view, "#staff-registration-form")
    end
  end

  describe "successful registration" do
    test "creates user account and redirects to login", %{conn: conn} do
      {raw_token, staff, _provider} = create_staff_with_invitation()

      {:ok, lv, _html} = live(conn, ~p"/users/staff-invitation/#{raw_token}")

      {:ok, _lv, html} =
        lv
        |> form("#staff-registration-form",
          user: %{
            name: "Jane Doe",
            password: "verylongpassword123!"
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "Account created"

      user = KlassHero.Repo.get_by!(User, email: staff.email)
      assert user.intended_roles == [:staff]
    end
  end

  describe "staff registration grants no provider role" do
    test "does not render a provider opt-in checkbox", %{conn: conn} do
      {raw_token, _staff, _provider} = create_staff_with_invitation()

      {:ok, view, _html} = live(conn, ~p"/users/staff-invitation/#{raw_token}")

      refute has_element?(view, "input[name='user[also_provider]']")
    end

    test "registration grants :staff only, never :provider (ADR-0005)", %{conn: conn} do
      {raw_token, staff, _provider} = create_staff_with_invitation()

      {:ok, lv, _html} = live(conn, ~p"/users/staff-invitation/#{raw_token}")

      {:ok, _lv, html} =
        lv
        |> form("#staff-registration-form",
          user: %{
            name: "Jane Doe",
            password: "verylongpassword123!"
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "Account created"

      user = KlassHero.Repo.get_by!(User, email: staff.email)
      assert user.intended_roles == [:staff]
      refute :provider in user.intended_roles
    end
  end

  describe "form validation errors" do
    test "shows error when password is too short", %{conn: conn} do
      {raw_token, _staff, _provider} = create_staff_with_invitation()

      {:ok, lv, _html} = live(conn, ~p"/users/staff-invitation/#{raw_token}")

      result =
        lv
        |> form("#staff-registration-form",
          user: %{
            name: "Jane Doe",
            password: "short"
          }
        )
        |> render_submit()

      assert result =~ "at least 12 character"
    end

    test "shows error when name is missing", %{conn: conn} do
      {raw_token, _staff, _provider} = create_staff_with_invitation()

      {:ok, lv, _html} = live(conn, ~p"/users/staff-invitation/#{raw_token}")

      result =
        lv
        |> form("#staff-registration-form",
          user: %{
            name: "",
            password: "verylongpassword123!"
          }
        )
        |> render_submit()

      assert result =~ "can&#39;t be blank"
    end

    test "validate event updates form without submitting", %{conn: conn} do
      {raw_token, _staff, _provider} = create_staff_with_invitation()

      {:ok, lv, _html} = live(conn, ~p"/users/staff-invitation/#{raw_token}")

      _result =
        lv
        |> form("#staff-registration-form",
          user: %{
            name: "J",
            password: ""
          }
        )
        |> render_change()

      assert has_element?(lv, "#staff-registration-form")
    end
  end

  describe "accept-screen mode branches (link to existing account, #967)" do
    test "anonymous + unknown email → registration form", %{conn: conn} do
      {raw_token, _staff, _provider} = create_staff_with_invitation()

      {:ok, lv, _html} = live(conn, ~p"/users/staff-invitation/#{raw_token}")

      assert has_element?(lv, "#staff-registration-form")
      refute has_element?(lv, "#staff-invite-link-button")
    end

    test "anonymous + existing account → must-log-in prompt, no form", %{conn: conn} do
      existing = user_fixture()
      {raw_token, _staff, _provider} = create_staff_with_invitation(email: existing.email)

      {:ok, lv, _html} = live(conn, ~p"/users/staff-invitation/#{raw_token}")

      assert has_element?(lv, "#staff-invite-login-prompt")
      refute has_element?(lv, "#staff-registration-form")
    end

    test "logged in as the invited email → one-click link button", %{conn: conn} do
      user = user_fixture()
      {raw_token, _staff, _provider} = create_staff_with_invitation(email: user.email)

      conn = log_in_user(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/users/staff-invitation/#{raw_token}")

      assert has_element?(lv, "#staff-invite-link-button")
      refute has_element?(lv, "#staff-registration-form")
    end

    test "logged in as a different account → wrong-account message", %{conn: conn} do
      logged_in = user_fixture()
      {raw_token, staff, _provider} = create_staff_with_invitation()

      conn = log_in_user(conn, logged_in)
      {:ok, lv, html} = live(conn, ~p"/users/staff-invitation/#{raw_token}")

      assert has_element?(lv, "#staff-invite-wrong-account")
      refute has_element?(lv, "#staff-invite-link-button")
      assert html =~ staff.email
    end
  end

  describe "one-click link (#967)" do
    test "links the account, grants :staff, and navigates to the staff dashboard", %{conn: conn} do
      user = user_fixture(intended_roles: [:parent])
      {raw_token, staff, _provider} = create_staff_with_invitation(email: user.email)

      conn = log_in_user(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/users/staff-invitation/#{raw_token}")

      lv |> element("#staff-invite-link-button") |> render_click()

      assert_redirect(lv, ~p"/staff/dashboard")

      # Race-free: both writes completed synchronously before the redirect.
      reloaded = KlassHero.Repo.get!(User, user.id)
      assert :staff in reloaded.intended_roles
      assert :parent in reloaded.intended_roles

      scope = Scope.for_user(reloaded) |> Scope.resolve_roles()
      assert :staff in scope.roles

      assert {:ok, linked} = KlassHero.Provider.get_staff_member(staff.id)
      assert linked.user_id == user.id
      assert linked.invitation_status == :accepted
    end
  end
end
