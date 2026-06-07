defmodule KlassHeroWeb.Admin.AccountLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias KlassHero.Accounts.User

  describe "admin access control" do
    setup :register_and_log_in_admin

    test "admin can access /admin/accounts", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/accounts")
      assert html =~ "Accounts"
    end

    test "new user button is not shown on index", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/accounts")
      refute has_element?(view, "a", "New")
    end
  end

  describe "non-admin access control" do
    setup :register_and_log_in_user

    test "non-admin is redirected from /admin/accounts", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/admin/accounts")
      assert flash["error"] =~ "access"
    end

    test "non-admin is redirected from /admin/accounts/:id/show", %{conn: conn} do
      user = KlassHero.AccountsFixtures.user_fixture(%{name: "Target"})

      assert {:error, {:redirect, %{to: "/", flash: flash}}} =
               live(conn, ~p"/admin/accounts/#{user.id}/show")

      assert flash["error"] =~ "access"
    end

    test "non-admin is redirected from /admin/accounts/:id/edit", %{conn: conn} do
      user = KlassHero.AccountsFixtures.user_fixture(%{name: "Target"})

      assert {:error, {:redirect, %{to: "/", flash: flash}}} =
               live(conn, ~p"/admin/accounts/#{user.id}/edit")

      assert flash["error"] =~ "access"
    end
  end

  describe "unauthenticated access control" do
    test "unauthenticated user is redirected from /admin/accounts", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin/accounts")
    end
  end

  describe "user list" do
    setup :register_and_log_in_admin

    test "displays users in the table", %{conn: conn, user: admin} do
      regular_user = KlassHero.AccountsFixtures.user_fixture(%{name: "Regular Test User"})

      {:ok, view, _html} = live(conn, ~p"/admin/accounts")

      # Backpex renders table data after connected mount via handle_params
      assert has_element?(view, "td", admin.email)
      assert has_element?(view, "td", admin.name)
      assert has_element?(view, "td", regular_user.email)
      assert has_element?(view, "td", regular_user.name)
    end
  end

  describe "show view" do
    setup :register_and_log_in_admin

    test "admin can view account details", %{conn: conn} do
      user = KlassHero.AccountsFixtures.user_fixture(%{name: "Show Target"})

      KlassHero.Factory.insert(:parent_profile_schema,
        identity_id: user.id,
        subscription_tier: "active"
      )

      {:ok, view, _html} = live(conn, ~p"/admin/accounts/#{user.id}/show")

      assert has_element?(view, "dd", user.email)
      assert has_element?(view, "dd", "Show Target")
      assert has_element?(view, "span", "Parent")
      assert has_element?(view, "span", "Active")
    end
  end

  describe "self-edit restriction" do
    setup :register_and_log_in_admin

    test "admin cannot edit their own record", %{conn: conn, user: admin} do
      assert_raise Backpex.ForbiddenError, fn ->
        live(conn, ~p"/admin/accounts/#{admin.id}/edit")
      end
    end
  end

  describe "roles badges" do
    setup :register_and_log_in_admin

    test "displays Parent badge for user with parent profile", %{conn: conn} do
      user = KlassHero.AccountsFixtures.user_fixture(%{name: "Parent User"})
      KlassHero.Factory.insert(:parent_profile_schema, identity_id: user.id)

      {:ok, view, _html} = live(conn, ~p"/admin/accounts")

      assert has_element?(view, "span", "Parent")
    end

    test "displays Provider badge for user with provider profile", %{conn: conn} do
      user = KlassHero.AccountsFixtures.user_fixture(%{name: "Provider User"})

      KlassHero.Factory.insert(:provider_profile_schema,
        identity_id: user.id,
        business_name: "Test Biz"
      )

      {:ok, view, _html} = live(conn, ~p"/admin/accounts")

      assert has_element?(view, "span", "Provider")
    end

    test "displays Admin badge for admin user", %{conn: conn} do
      _admin_user =
        KlassHero.AccountsFixtures.user_fixture(%{name: "Other Admin", is_admin: true})

      {:ok, view, _html} = live(conn, ~p"/admin/accounts")

      # The logged-in admin also has Admin badge, but we check for the other admin
      assert has_element?(view, "span", "Admin")
    end

    test "displays multiple badges for dual-role user", %{conn: conn} do
      user = KlassHero.AccountsFixtures.user_fixture(%{name: "Dual Role"})
      KlassHero.Factory.insert(:parent_profile_schema, identity_id: user.id)

      KlassHero.Factory.insert(:provider_profile_schema,
        identity_id: user.id,
        business_name: "Dual Biz"
      )

      {:ok, view, _html} = live(conn, ~p"/admin/accounts")

      assert has_element?(view, "span", "Parent")
      assert has_element?(view, "span", "Provider")
    end

    test "displays User badge for user with no profile and not admin", %{conn: conn} do
      _bare_user = KlassHero.AccountsFixtures.user_fixture(%{name: "Bare User"})

      {:ok, view, _html} = live(conn, ~p"/admin/accounts")

      assert has_element?(view, "span", "User")
    end
  end

  describe "subscription badges" do
    setup :register_and_log_in_admin

    test "displays Explorer badge for parent with explorer tier", %{conn: conn} do
      user = KlassHero.AccountsFixtures.user_fixture(%{name: "Explorer Parent"})

      KlassHero.Factory.insert(:parent_profile_schema,
        identity_id: user.id,
        subscription_tier: "explorer"
      )

      {:ok, view, _html} = live(conn, ~p"/admin/accounts")

      assert has_element?(view, "span", "Explorer")
    end

    test "displays Active badge for parent with active tier", %{conn: conn} do
      user = KlassHero.AccountsFixtures.user_fixture(%{name: "Active Parent"})

      KlassHero.Factory.insert(:parent_profile_schema,
        identity_id: user.id,
        subscription_tier: "active"
      )

      {:ok, view, _html} = live(conn, ~p"/admin/accounts")

      assert has_element?(view, "span", "Active")
    end

    test "displays generic Provider badge for provider accounts", %{conn: conn} do
      # Provider tiers removed (ADR-0004): one badge for all providers
      user = KlassHero.AccountsFixtures.user_fixture(%{name: "Some Provider"})

      KlassHero.Factory.insert(:provider_profile_schema,
        identity_id: user.id,
        business_name: "Some Biz"
      )

      {:ok, view, _html} = live(conn, ~p"/admin/accounts")

      assert has_element?(view, "span", "Provider")
    end

    test "displays parent tier and Provider badge for dual-role user", %{conn: conn} do
      user = KlassHero.AccountsFixtures.user_fixture(%{name: "Dual Role"})

      KlassHero.Factory.insert(:parent_profile_schema,
        identity_id: user.id,
        subscription_tier: "active"
      )

      KlassHero.Factory.insert(:provider_profile_schema,
        identity_id: user.id,
        business_name: "Dual Role Biz"
      )

      {:ok, view, _html} = live(conn, ~p"/admin/accounts")

      assert has_element?(view, "span", "Active")
      assert has_element?(view, "span", "Provider")
    end

    test "displays dash for user with no profiles", %{conn: conn} do
      _bare = KlassHero.AccountsFixtures.user_fixture(%{name: "No Sub User"})

      {:ok, view, _html} = live(conn, ~p"/admin/accounts")

      # The em-dash is rendered for users without any profiles
      assert render(view) =~ "—"
    end
  end

  describe "admin toggle" do
    setup :register_and_log_in_admin

    test "admin can promote user to admin", %{conn: conn} do
      target_user = KlassHero.AccountsFixtures.user_fixture(%{name: "Promote Target"})
      assert target_user.is_admin == false

      {:ok, view, _html} = live(conn, ~p"/admin/accounts/#{target_user.id}/edit")

      view
      |> form("#resource-form", %{change: %{is_admin: true}})
      |> render_submit(%{"save-type" => "save"})

      updated = KlassHero.Repo.get!(User, target_user.id)
      assert updated.is_admin == true
    end

    test "admin can demote admin to regular user", %{conn: conn} do
      target_user =
        KlassHero.AccountsFixtures.user_fixture(%{name: "Demote Target", is_admin: true})

      assert target_user.is_admin == true

      {:ok, view, _html} = live(conn, ~p"/admin/accounts/#{target_user.id}/edit")

      view
      |> form("#resource-form", %{change: %{is_admin: false}})
      |> render_submit(%{"save-type" => "save"})

      updated = KlassHero.Repo.get!(User, target_user.id)
      assert updated.is_admin == false
    end
  end
end
