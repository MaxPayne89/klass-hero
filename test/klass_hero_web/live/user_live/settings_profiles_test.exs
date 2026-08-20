defmodule KlassHeroWeb.UserLive.SettingsProfilesTest do
  @moduledoc """
  The Profiles section of account settings — where a person gains the persona
  they lack (#899).

  Assertions target element ids rather than copy: the ids are the contract the
  chrome and the two mid-flow redirects (booking, children) point at.
  """
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.AccountsFixtures
  import Phoenix.LiveViewTest

  alias KlassHero.Family
  alias KlassHero.Provider

  defp parent_only(_context) do
    user = user_fixture(intended_roles: [:parent])
    {:ok, _parent} = Family.create_parent_profile(%{identity_id: user.id})
    %{user: user}
  end

  defp provider_only(_context) do
    user = user_fixture(intended_roles: [:provider])

    {:ok, _provider} =
      Provider.create_provider_profile(%{identity_id: user.id, business_name: "Test Business"})

    %{user: user}
  end

  describe "which profiles are offered" do
    setup [:parent_only]

    test "a parent is offered a business profile, not another family one", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/users/settings")

      assert has_element?(view, "#add-provider-profile")
      refute has_element?(view, "#add-parent-profile")
    end
  end

  describe "which profiles are offered — provider" do
    setup [:provider_only]

    test "a provider is offered a family profile, not another business one", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/users/settings")

      assert has_element?(view, "#add-parent-profile")
      refute has_element?(view, "#add-provider-profile")
    end

    # Staff is an employment link to someone else's business (ADR-0005), so it
    # is never self-grantable and must not appear here.
    test "staff is never offered", %{conn: conn, user: user} do
      {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/users/settings")

      refute has_element?(view, "#add-staff-profile")
    end
  end

  describe "adding a family profile" do
    setup [:provider_only]

    test "asks for confirmation before granting anything", %{conn: conn, user: user} do
      {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/users/settings")

      refute has_element?(view, "#add-parent-profile-confirm")

      view |> element("#add-parent-profile-button") |> render_click()

      assert has_element?(view, "#add-parent-profile-confirm")
      # The persona is not granted until the confirm step is taken.
      assert {:error, :not_found} = Family.get_parent_by_identity(user.id)
    end

    test "backing out grants nothing", %{conn: conn, user: user} do
      {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/users/settings")

      view |> element("#add-parent-profile-button") |> render_click()
      view |> element("#add-parent-profile-cancel") |> render_click()

      refute has_element?(view, "#add-parent-profile-confirm")
      assert {:error, :not_found} = Family.get_parent_by_identity(user.id)
    end

    test "confirming grants the persona and lands on children", %{conn: conn, user: user} do
      {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/users/settings")

      view |> element("#add-parent-profile-button") |> render_click()

      assert {:error, {:live_redirect, %{to: "/settings/children"}}} =
               view |> element("#add-parent-profile-confirm") |> render_click()

      assert {:ok, parent} = Family.get_parent_by_identity(user.id)
      assert parent.identity_id == user.id
    end
  end

  describe "adding a business profile" do
    setup [:parent_only]

    test "confirming grants the persona and lands on the completion flow", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/users/settings")

      view |> element("#add-provider-profile-button") |> render_click()

      assert {:error, {:live_redirect, %{to: "/provider/complete-profile"}}} =
               view |> element("#add-provider-profile-confirm") |> render_click()

      assert {:ok, profile} = Provider.get_provider_by_identity(user.id)
      assert profile.profile_status == :draft
    end
  end

  describe "a person who already holds both" do
    setup [:parent_only]

    test "sees no Profiles section at all", %{conn: conn, user: user} do
      {:ok, _provider} =
        Provider.create_provider_profile(%{identity_id: user.id, business_name: "Test Business"})

      {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/users/settings")

      refute has_element?(view, "#profiles")
    end
  end
end
