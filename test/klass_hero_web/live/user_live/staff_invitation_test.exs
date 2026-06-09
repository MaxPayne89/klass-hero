defmodule KlassHeroWeb.UserLive.StaffInvitationTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.AccountsFixtures
  import KlassHero.ProviderFixtures
  import Phoenix.LiveViewTest

  alias KlassHero.Accounts.User

  defp create_staff_with_invitation(opts \\ []) do
    provider = provider_profile_fixture()
    raw_bytes = :crypto.strong_rand_bytes(32)
    raw_token = Base.url_encode64(raw_bytes, padding: false)
    token_hash = :crypto.hash(:sha256, raw_bytes)

    sent_at = Keyword.get(opts, :invitation_sent_at, DateTime.utc_now())

    staff =
      staff_member_fixture(%{
        provider_id: provider.id,
        first_name: "Jane",
        last_name: "Doe",
        email: "invited-#{System.unique_integer([:positive])}@example.com",
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

  describe "registration with duplicate email" do
    test "shows validation error when email is already taken", %{conn: conn} do
      {raw_token, staff, _provider} = create_staff_with_invitation()

      # Create another user with the same email before registration
      user_fixture(email: staff.email)

      {:ok, lv, _html} = live(conn, ~p"/users/staff-invitation/#{raw_token}")

      result =
        lv
        |> form("#staff-registration-form",
          user: %{
            name: "Jane Doe",
            password: "verylongpassword123!"
          }
        )
        |> render_submit()

      assert result =~ "has already been taken"
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
end
