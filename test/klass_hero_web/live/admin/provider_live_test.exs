defmodule KlassHeroWeb.Admin.ProviderLiveTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.ProviderFixtures
  import Phoenix.LiveViewTest

  alias KlassHero.Provider.ProviderProfile

  describe "admin access control" do
    setup :register_and_log_in_admin

    test "admin can access /admin/providers", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/providers")
      assert html =~ "Providers"
    end

    test "new provider button is not shown on index", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/providers")
      refute has_element?(view, "a", "New")
    end
  end

  describe "non-admin access control" do
    setup :register_and_log_in_user

    test "non-admin is redirected from /admin/providers", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/admin/providers")
      assert flash["error"] =~ "access"
    end
  end

  describe "unauthenticated access control" do
    test "unauthenticated user is redirected from /admin/providers", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin/providers")
    end
  end

  describe "provider list" do
    setup :register_and_log_in_admin

    test "displays providers in the table", %{conn: conn} do
      _provider = provider_profile_fixture(business_name: "Acme Activities")

      {:ok, view, _html} = live(conn, ~p"/admin/providers")

      assert has_element?(view, "td", "Acme Activities")
    end
  end

  describe "edit provider" do
    setup :register_and_log_in_admin

    test "admin can toggle verified status and sets audit fields", %{conn: conn, user: user} do
      provider = provider_profile_fixture(business_name: "Verify Me")

      {:ok, view, _html} = live(conn, ~p"/admin/providers/#{provider.id}/edit")

      view
      |> form("#resource-form", %{change: %{verified: true}})
      |> render_submit(%{"save-type" => "save"})

      schema =
        KlassHero.Repo.get!(
          ProviderProfile,
          provider.id
        )

      assert schema.verified == true
      assert schema.verified_at != nil
      assert schema.verified_by_id == user.id
    end

    test "admin can unverify and clears audit fields", %{conn: conn} do
      provider = provider_profile_fixture(business_name: "Unverify Me", verified: true)

      {:ok, view, _html} = live(conn, ~p"/admin/providers/#{provider.id}/edit")

      view
      |> form("#resource-form", %{change: %{verified: false}})
      |> render_submit(%{"save-type" => "save"})

      schema =
        KlassHero.Repo.get!(
          ProviderProfile,
          provider.id
        )

      assert schema.verified == false
      assert schema.verified_at == nil
      assert schema.verified_by_id == nil
    end

    test "edit form exposes no subscription tier field", %{conn: conn} do
      # Provider tiers removed (ADR-0004): admins only edit verification
      provider = provider_profile_fixture(business_name: "No Tier Field")

      {:ok, view, _html} = live(conn, ~p"/admin/providers/#{provider.id}/edit")

      refute has_element?(view, ~s([name="change[subscription_tier]"]))
    end
  end
end
