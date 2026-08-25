defmodule KlassHeroWeb.UserAuthAdminTest do
  use KlassHeroWeb.ConnCase, async: true

  # These exercise functions that *return* a socket or conn, so their assigns are the
  # return value under test — there is no rendered page to assert against instead.
  alias KlassHero.Accounts.Scope
  alias KlassHero.AccountsFixtures
  alias KlassHeroWeb.UserAuth
  alias Phoenix.LiveView

  @moduletag :plug_test

  # Helper to create a socket with the required assigns for on_mount hooks.
  # Phoenix LiveView's put_flash requires the :__changed__ and :flash assigns.
  defp build_socket(assigns) do
    %LiveView.Socket{
      endpoint: KlassHeroWeb.Endpoint,
      assigns: Map.merge(%{__changed__: %{}, flash: %{}}, assigns)
    }
  end

  describe "on_mount :require_admin" do
    test "allows admin users to access admin pages" do
      user = AccountsFixtures.user_fixture(%{is_admin: true})
      socket = build_socket(%{current_scope: Scope.for_user(user)})

      assert {:cont, _socket} = UserAuth.on_mount(:require_admin, %{}, %{}, socket)
    end

    test "redirects non-admin users" do
      user = AccountsFixtures.user_fixture(%{is_admin: false})
      socket = build_socket(%{current_scope: Scope.for_user(user)})

      assert {:halt, updated_socket} = UserAuth.on_mount(:require_admin, %{}, %{}, socket)

      assert updated_socket.redirected
      assert updated_socket.assigns.flash["error"] == "You don't have access to that page."
    end

    test "redirects when user is nil" do
      socket = build_socket(%{current_scope: Scope.for_user(nil)})

      assert {:halt, updated_socket} = UserAuth.on_mount(:require_admin, %{}, %{}, socket)

      assert updated_socket.redirected
      assert updated_socket.assigns.flash["error"] == "You don't have access to that page."
    end

    test "redirects when current_scope is nil" do
      socket = build_socket(%{current_scope: nil})

      assert {:halt, updated_socket} = UserAuth.on_mount(:require_admin, %{}, %{}, socket)

      assert updated_socket.redirected
      assert updated_socket.assigns.flash["error"] == "You don't have access to that page."
    end
  end
end
