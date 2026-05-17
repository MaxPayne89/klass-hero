defmodule KlassHeroWeb.UserAuthTest do
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.AccountsFixtures
  import KlassHero.ProviderFixtures

  alias KlassHero.Accounts
  alias KlassHero.Accounts.Scope
  alias KlassHero.Family
  alias KlassHero.Provider
  alias KlassHeroWeb.UserAuth
  alias Phoenix.LiveView
  alias Phoenix.Socket.Broadcast

  @remember_me_cookie "_klass_hero_web_user_remember_me"
  @remember_me_cookie_max_age 60 * 60 * 24 * 14

  setup %{conn: conn} do
    conn =
      conn
      |> Map.replace!(:secret_key_base, KlassHeroWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})

    %{user: %{user_fixture() | authenticated_at: DateTime.utc_now(:second)}, conn: conn}
  end

  describe "log_in_user/3" do
    test "stores the user token in the session", %{conn: conn, user: user} do
      conn = UserAuth.log_in_user(conn, user)
      assert token = get_session(conn, :user_token)
      assert get_session(conn, :live_socket_id) == "users_sessions:#{Base.url_encode64(token)}"
      assert redirected_to(conn) == ~p"/dashboard"
      assert Accounts.get_user_by_session_token(token)
    end

    test "clears everything previously stored in the session", %{conn: conn, user: user} do
      conn = conn |> put_session(:to_be_removed, "value") |> UserAuth.log_in_user(user)
      refute get_session(conn, :to_be_removed)
    end

    test "keeps session when re-authenticating", %{conn: conn, user: user} do
      conn =
        conn
        |> assign(:current_scope, Scope.for_user(user))
        |> put_session(:to_be_removed, "value")
        |> UserAuth.log_in_user(user)

      assert get_session(conn, :to_be_removed)
    end

    test "clears session when user does not match when re-authenticating", %{
      conn: conn,
      user: user
    } do
      other_user = user_fixture()

      conn =
        conn
        |> assign(:current_scope, Scope.for_user(other_user))
        |> put_session(:to_be_removed, "value")
        |> UserAuth.log_in_user(user)

      refute get_session(conn, :to_be_removed)
    end

    test "redirects to the configured path", %{conn: conn, user: user} do
      conn = conn |> put_session(:user_return_to, "/hello") |> UserAuth.log_in_user(user)
      assert redirected_to(conn) == "/hello"
    end

    test "writes a cookie if remember_me is configured", %{conn: conn, user: user} do
      conn = conn |> fetch_cookies() |> UserAuth.log_in_user(user, %{"remember_me" => "true"})
      assert get_session(conn, :user_token) == conn.cookies[@remember_me_cookie]
      assert get_session(conn, :user_remember_me) == true

      assert %{value: signed_token, max_age: max_age} = conn.resp_cookies[@remember_me_cookie]
      assert signed_token != get_session(conn, :user_token)
      assert max_age == @remember_me_cookie_max_age
    end

    test "redirects to parent dashboard when user is already logged in", %{conn: conn, user: user} do
      conn =
        conn
        |> assign(:current_scope, Scope.for_user(user))
        |> UserAuth.log_in_user(user)

      assert redirected_to(conn) == ~p"/dashboard"
    end

    test "redirects provider to provider dashboard", %{conn: conn} do
      provider_user = %{
        user_fixture(intended_roles: [:provider])
        | authenticated_at: DateTime.utc_now(:second)
      }

      conn = UserAuth.log_in_user(conn, provider_user)
      assert redirected_to(conn) == ~p"/provider/dashboard"
    end

    test "redirects dual-role user to provider dashboard", %{conn: conn} do
      dual_user = %{
        user_fixture(intended_roles: [:parent, :provider])
        | authenticated_at: DateTime.utc_now(:second)
      }

      conn = UserAuth.log_in_user(conn, dual_user)
      assert redirected_to(conn) == ~p"/provider/dashboard"
    end

    test "writes a cookie if remember_me was set in previous session", %{conn: conn, user: user} do
      conn = conn |> fetch_cookies() |> UserAuth.log_in_user(user, %{"remember_me" => "true"})
      assert get_session(conn, :user_token) == conn.cookies[@remember_me_cookie]
      assert get_session(conn, :user_remember_me) == true

      conn =
        conn
        |> recycle()
        |> Map.replace!(:secret_key_base, KlassHeroWeb.Endpoint.config(:secret_key_base))
        |> fetch_cookies()
        |> init_test_session(%{user_remember_me: true})

      # the conn is already logged in and has the remember_me cookie set,
      # now we log in again and even without explicitly setting remember_me,
      # the cookie should be set again
      conn = conn |> UserAuth.log_in_user(user, %{})
      assert %{value: signed_token, max_age: max_age} = conn.resp_cookies[@remember_me_cookie]
      assert signed_token != get_session(conn, :user_token)
      assert max_age == @remember_me_cookie_max_age
      assert get_session(conn, :user_remember_me) == true
    end
  end

  describe "logout_user/1" do
    test "erases session and cookies", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)

      conn =
        conn
        |> put_session(:user_token, user_token)
        |> put_req_cookie(@remember_me_cookie, user_token)
        |> fetch_cookies()
        |> UserAuth.log_out_user()

      refute get_session(conn, :user_token)
      refute conn.cookies[@remember_me_cookie]
      assert %{max_age: 0} = conn.resp_cookies[@remember_me_cookie]
      assert redirected_to(conn) == ~p"/"
      refute Accounts.get_user_by_session_token(user_token)
    end

    test "broadcasts to the given live_socket_id", %{conn: conn} do
      live_socket_id = "users_sessions:abcdef-token"
      KlassHeroWeb.Endpoint.subscribe(live_socket_id)

      conn
      |> put_session(:live_socket_id, live_socket_id)
      |> UserAuth.log_out_user()

      assert_receive %Broadcast{event: "disconnect", topic: ^live_socket_id}
    end

    test "works even if user is already logged out", %{conn: conn} do
      conn = conn |> fetch_cookies() |> UserAuth.log_out_user()
      refute get_session(conn, :user_token)
      assert %{max_age: 0} = conn.resp_cookies[@remember_me_cookie]
      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "fetch_current_scope_for_user/2" do
    test "authenticates user from session", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)

      conn =
        conn |> put_session(:user_token, user_token) |> UserAuth.fetch_current_scope_for_user([])

      assert conn.assigns.current_scope.user.id == user.id
      assert conn.assigns.current_scope.user.authenticated_at == user.authenticated_at
      assert get_session(conn, :user_token) == user_token
    end

    test "authenticates user from cookies", %{conn: conn, user: user} do
      logged_in_conn =
        conn |> fetch_cookies() |> UserAuth.log_in_user(user, %{"remember_me" => "true"})

      user_token = logged_in_conn.cookies[@remember_me_cookie]
      %{value: signed_token} = logged_in_conn.resp_cookies[@remember_me_cookie]

      conn =
        conn
        |> put_req_cookie(@remember_me_cookie, signed_token)
        |> UserAuth.fetch_current_scope_for_user([])

      assert conn.assigns.current_scope.user.id == user.id
      assert conn.assigns.current_scope.user.authenticated_at == user.authenticated_at
      assert get_session(conn, :user_token) == user_token
      assert get_session(conn, :user_remember_me)

      assert get_session(conn, :live_socket_id) ==
               "users_sessions:#{Base.url_encode64(user_token)}"
    end

    test "does not authenticate if data is missing", %{conn: conn, user: user} do
      _ = Accounts.generate_user_session_token(user)
      conn = UserAuth.fetch_current_scope_for_user(conn, [])
      refute get_session(conn, :user_token)
      refute conn.assigns.current_scope
    end

    test "reissues a new token after a few days and refreshes cookie", %{conn: conn, user: user} do
      logged_in_conn =
        conn |> fetch_cookies() |> UserAuth.log_in_user(user, %{"remember_me" => "true"})

      token = logged_in_conn.cookies[@remember_me_cookie]
      %{value: signed_token} = logged_in_conn.resp_cookies[@remember_me_cookie]

      offset_user_token(token, -10, :day)
      {user, _} = Accounts.get_user_by_session_token(token)

      conn =
        conn
        |> put_session(:user_token, token)
        |> put_session(:user_remember_me, true)
        |> put_req_cookie(@remember_me_cookie, signed_token)
        |> UserAuth.fetch_current_scope_for_user([])

      assert conn.assigns.current_scope.user.id == user.id
      assert conn.assigns.current_scope.user.authenticated_at == user.authenticated_at
      assert new_token = get_session(conn, :user_token)
      assert new_token != token
      assert %{value: new_signed_token, max_age: max_age} = conn.resp_cookies[@remember_me_cookie]
      assert new_signed_token != signed_token
      assert max_age == @remember_me_cookie_max_age
    end
  end

  describe "on_mount :mount_current_scope" do
    setup %{conn: conn} do
      %{conn: UserAuth.fetch_current_scope_for_user(conn, [])}
    end

    test "assigns current_scope based on a valid user_token", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      {:cont, updated_socket} =
        UserAuth.on_mount(:mount_current_scope, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_scope.user.id == user.id
    end

    test "assigns nil to current_scope assign if there isn't a valid user_token", %{conn: conn} do
      user_token = "invalid_token"
      session = conn |> put_session(:user_token, user_token) |> get_session()

      {:cont, updated_socket} =
        UserAuth.on_mount(:mount_current_scope, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_scope == nil
    end

    test "assigns nil to current_scope assign if there isn't a user_token", %{conn: conn} do
      session = conn |> get_session()

      {:cont, updated_socket} =
        UserAuth.on_mount(:mount_current_scope, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_scope == nil
    end
  end

  describe "on_mount :require_authenticated" do
    test "authenticates current_scope based on a valid user_token", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      {:cont, updated_socket} =
        UserAuth.on_mount(:require_authenticated, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_scope.user.id == user.id
    end

    test "redirects to login page if there isn't a valid user_token", %{conn: conn} do
      user_token = "invalid_token"
      session = conn |> put_session(:user_token, user_token) |> get_session()

      socket = %LiveView.Socket{
        endpoint: KlassHeroWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:halt, updated_socket} = UserAuth.on_mount(:require_authenticated, %{}, session, socket)
      assert updated_socket.assigns.current_scope == nil
    end

    test "redirects to login page if there isn't a user_token", %{conn: conn} do
      session = conn |> get_session()

      socket = %LiveView.Socket{
        endpoint: KlassHeroWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:halt, updated_socket} = UserAuth.on_mount(:require_authenticated, %{}, session, socket)
      assert updated_socket.assigns.current_scope == nil
    end
  end

  describe "on_mount :require_sudo_mode" do
    test "allows users that have authenticated in the last 10 minutes", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      socket = %LiveView.Socket{
        endpoint: KlassHeroWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      assert {:cont, _updated_socket} =
               UserAuth.on_mount(:require_sudo_mode, %{}, session, socket)
    end

    test "redirects when authentication is too old", %{conn: conn, user: user} do
      eleven_minutes_ago = DateTime.utc_now(:second) |> DateTime.add(-11, :minute)
      user = %{user | authenticated_at: eleven_minutes_ago}
      user_token = Accounts.generate_user_session_token(user)
      {user, token_inserted_at} = Accounts.get_user_by_session_token(user_token)
      assert DateTime.after?(token_inserted_at, user.authenticated_at)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      socket = %LiveView.Socket{
        endpoint: KlassHeroWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      assert {:halt, _updated_socket} =
               UserAuth.on_mount(:require_sudo_mode, %{}, session, socket)
    end
  end

  describe "on_mount :require_parent" do
    test "continues when user has parent profile", %{conn: conn} do
      user = user_fixture()

      {:ok, _parent} =
        Family.create_parent_profile(%{
          identity_id: user.id,
          display_name: user.name
        })

      user_token = Accounts.generate_user_session_token(user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      socket = %LiveView.Socket{
        endpoint: KlassHeroWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:cont, updated_socket} = UserAuth.on_mount(:require_parent, %{}, session, socket)

      assert updated_socket.assigns.current_scope.user.id == user.id
      assert updated_socket.assigns.current_scope.parent != nil
      assert Scope.parent?(updated_socket.assigns.current_scope)
    end

    test "halts and redirects when user has no parent profile", %{conn: conn} do
      user = user_fixture()
      user_token = Accounts.generate_user_session_token(user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      socket = %LiveView.Socket{
        endpoint: KlassHeroWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:halt, updated_socket} = UserAuth.on_mount(:require_parent, %{}, session, socket)

      assert updated_socket.assigns.flash["error"] ==
               "You must have a parent profile to access this page."
    end

    test "halts and redirects when user is not authenticated", %{conn: conn} do
      session = get_session(conn)

      socket = %LiveView.Socket{
        endpoint: KlassHeroWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:halt, updated_socket} = UserAuth.on_mount(:require_parent, %{}, session, socket)

      assert updated_socket.assigns.flash["error"] ==
               "You must be authenticated to access this page."
    end
  end

  describe "on_mount :require_provider" do
    test "continues when user has provider profile", %{conn: conn} do
      user = user_fixture()

      {:ok, _provider} =
        Provider.create_provider_profile(%{
          identity_id: user.id,
          business_name: "Test Business"
        })

      user_token = Accounts.generate_user_session_token(user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      socket = %LiveView.Socket{
        endpoint: KlassHeroWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:cont, updated_socket} = UserAuth.on_mount(:require_provider, %{}, session, socket)

      assert updated_socket.assigns.current_scope.user.id == user.id
      assert updated_socket.assigns.current_scope.provider != nil
      assert Scope.provider?(updated_socket.assigns.current_scope)
    end

    test "halts and redirects when user has no provider profile", %{conn: conn} do
      user = user_fixture()
      user_token = Accounts.generate_user_session_token(user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      socket = %LiveView.Socket{
        endpoint: KlassHeroWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:halt, updated_socket} = UserAuth.on_mount(:require_provider, %{}, session, socket)

      assert updated_socket.assigns.flash["error"] ==
               "You must have a provider profile to access this page."
    end

    test "halts and redirects when user is not authenticated", %{conn: conn} do
      session = get_session(conn)

      socket = %LiveView.Socket{
        endpoint: KlassHeroWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:halt, updated_socket} = UserAuth.on_mount(:require_provider, %{}, session, socket)

      assert updated_socket.assigns.flash["error"] ==
               "You must be authenticated to access this page."
    end
  end

  describe "on_mount :redirect_provider_or_staff_from_parent_routes" do
    test "redirects provider users to provider dashboard", %{conn: conn} do
      user = user_fixture()

      {:ok, _provider} =
        Provider.create_provider_profile(%{
          identity_id: user.id,
          business_name: "Test Business"
        })

      user_token = Accounts.generate_user_session_token(user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      socket = %LiveView.Socket{
        endpoint: KlassHeroWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:halt, updated_socket} =
        UserAuth.on_mount(:redirect_provider_or_staff_from_parent_routes, %{}, session, socket)

      assert {:redirect, redirect_opts} = updated_socket.redirected
      assert redirect_opts.to == "/provider/dashboard"
    end

    test "continues for non-provider users", %{conn: conn} do
      user = user_fixture()
      user_token = Accounts.generate_user_session_token(user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      socket = %LiveView.Socket{
        endpoint: KlassHeroWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:cont, updated_socket} =
        UserAuth.on_mount(:redirect_provider_or_staff_from_parent_routes, %{}, session, socket)

      assert updated_socket.assigns.current_scope.user.id == user.id
    end

    test "continues for parent users", %{conn: conn} do
      user = user_fixture()

      {:ok, _parent} =
        Family.create_parent_profile(%{
          identity_id: user.id,
          display_name: user.name
        })

      user_token = Accounts.generate_user_session_token(user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      socket = %LiveView.Socket{
        endpoint: KlassHeroWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:cont, updated_socket} =
        UserAuth.on_mount(:redirect_provider_or_staff_from_parent_routes, %{}, session, socket)

      assert updated_socket.assigns.current_scope.user.id == user.id
      assert Scope.parent?(updated_socket.assigns.current_scope)
    end

    test "continues when user is not authenticated", %{conn: conn} do
      session = get_session(conn)

      socket = %LiveView.Socket{
        endpoint: KlassHeroWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:cont, _updated_socket} =
        UserAuth.on_mount(:redirect_provider_or_staff_from_parent_routes, %{}, session, socket)
    end

    test "redirects staff provider users to staff dashboard", %{conn: conn} do
      user = user_fixture(intended_roles: [:staff_provider])
      provider = provider_profile_fixture()

      staff_member_fixture(%{
        provider_id: provider.id,
        user_id: user.id,
        active: true,
        invitation_status: :accepted
      })

      user_token = Accounts.generate_user_session_token(user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      socket = %LiveView.Socket{
        endpoint: KlassHeroWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:halt, updated_socket} =
        UserAuth.on_mount(:redirect_provider_or_staff_from_parent_routes, %{}, session, socket)

      assert {:redirect, redirect_opts} = updated_socket.redirected
      assert redirect_opts.to == "/staff/dashboard"
    end

    test "continues for staff_provider user with no active staff record", %{conn: conn} do
      user = user_fixture(intended_roles: [:staff_provider])

      user_token = Accounts.generate_user_session_token(user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      socket = %LiveView.Socket{
        endpoint: KlassHeroWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:cont, updated_socket} =
        UserAuth.on_mount(:redirect_provider_or_staff_from_parent_routes, %{}, session, socket)

      assert updated_socket.assigns.current_scope.user.id == user.id
    end

    test "redirects dual-role user to provider dashboard (provider takes precedence)", %{
      conn: conn
    } do
      %{user: user} = dual_role_user_fixture()

      user_token = Accounts.generate_user_session_token(user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      socket = %LiveView.Socket{
        endpoint: KlassHeroWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:halt, updated_socket} =
        UserAuth.on_mount(:redirect_provider_or_staff_from_parent_routes, %{}, session, socket)

      assert {:redirect, redirect_opts} = updated_socket.redirected
      assert redirect_opts.to == "/provider/dashboard"
    end
  end

  describe "require_authenticated_user/2" do
    setup %{conn: conn} do
      %{conn: UserAuth.fetch_current_scope_for_user(conn, [])}
    end

    test "redirects if user is not authenticated", %{conn: conn} do
      conn = conn |> fetch_flash() |> UserAuth.require_authenticated_user([])
      assert conn.halted

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "You must log in to access this page."
    end

    test "stores the path to redirect to on GET", %{conn: conn} do
      halted_conn =
        %{conn | path_info: ["foo"], query_string: ""}
        |> fetch_flash()
        |> UserAuth.require_authenticated_user([])

      assert halted_conn.halted
      assert get_session(halted_conn, :user_return_to) == "/foo"

      halted_conn =
        %{conn | path_info: ["foo"], query_string: "bar=baz"}
        |> fetch_flash()
        |> UserAuth.require_authenticated_user([])

      assert halted_conn.halted
      assert get_session(halted_conn, :user_return_to) == "/foo?bar=baz"

      halted_conn =
        %{conn | path_info: ["foo"], query_string: "bar", method: "POST"}
        |> fetch_flash()
        |> UserAuth.require_authenticated_user([])

      assert halted_conn.halted
      refute get_session(halted_conn, :user_return_to)
    end

    test "does not redirect if user is authenticated", %{conn: conn, user: user} do
      conn =
        conn
        |> assign(:current_scope, Scope.for_user(user))
        |> UserAuth.require_authenticated_user([])

      refute conn.halted
      refute conn.status
    end
  end

  describe "disconnect_sessions/1" do
    test "broadcasts disconnect messages for each token" do
      tokens = [%{token: "token1"}, %{token: "token2"}]

      for %{token: token} <- tokens do
        KlassHeroWeb.Endpoint.subscribe("users_sessions:#{Base.url_encode64(token)}")
      end

      UserAuth.disconnect_sessions(tokens)

      assert_receive %Broadcast{
        event: "disconnect",
        topic: "users_sessions:dG9rZW4x"
      }

      assert_receive %Broadcast{
        event: "disconnect",
        topic: "users_sessions:dG9rZW4y"
      }
    end
  end

  describe "signed_in_path/1" do
    test "redirects staff_provider to staff dashboard" do
      user = %Accounts.User{intended_roles: [:staff_provider]}
      assert UserAuth.signed_in_path(user) == ~p"/staff/dashboard"
    end

    test "redirects provider to provider dashboard" do
      user = %Accounts.User{intended_roles: [:provider]}
      assert UserAuth.signed_in_path(user) == ~p"/provider/dashboard"
    end

    test "redirects parent to parent dashboard" do
      user = %Accounts.User{intended_roles: [:parent]}
      assert UserAuth.signed_in_path(user) == ~p"/dashboard"
    end

    test "redirects user with no roles to parent dashboard" do
      user = %Accounts.User{intended_roles: []}
      assert UserAuth.signed_in_path(user) == ~p"/dashboard"
    end

    test "provider takes precedence over staff_provider for dual-role users" do
      user = %Accounts.User{intended_roles: [:provider, :staff_provider]}
      assert UserAuth.signed_in_path(user) == ~p"/provider/dashboard"
    end

    test "falls back to root for nil user" do
      assert UserAuth.signed_in_path(nil) == ~p"/"
    end

    test "is_admin does not change role-based redirect (role wins)" do
      cases = [
        {[], ~p"/dashboard", "admin-only user lands on parent dashboard"},
        {[:parent], ~p"/dashboard", "parent+admin lands on parent dashboard"},
        {[:provider], ~p"/provider/dashboard", "provider+admin lands on provider dashboard"},
        {[:staff_provider], ~p"/staff/dashboard", "staff+admin lands on staff dashboard"}
      ]

      for {roles, expected, label} <- cases do
        user = %Accounts.User{intended_roles: roles, is_admin: true}

        assert UserAuth.signed_in_path(user) == expected,
               "#{label}: roles=#{inspect(roles)}"
      end
    end
  end

  describe "dashboard_path/1" do
    test "returns staff dashboard path for staff_provider" do
      user = %Accounts.User{intended_roles: [:staff_provider]}
      assert UserAuth.dashboard_path(user) == ~p"/staff/dashboard"
    end

    test "returns provider dashboard path for provider" do
      user = %Accounts.User{intended_roles: [:provider]}
      assert UserAuth.dashboard_path(user) == ~p"/provider/dashboard"
    end

    test "returns parent dashboard path for parent" do
      user = %Accounts.User{intended_roles: [:parent]}
      assert UserAuth.dashboard_path(user) == ~p"/dashboard"
    end

    test "returns parent dashboard path for empty roles" do
      user = %Accounts.User{intended_roles: []}
      assert UserAuth.dashboard_path(user) == ~p"/dashboard"
    end

    test "provider takes precedence over staff_provider for dual-role users" do
      user = %Accounts.User{intended_roles: [:provider, :staff_provider]}
      assert UserAuth.dashboard_path(user) == ~p"/provider/dashboard"
    end

    test "falls back to parent dashboard for nil" do
      assert UserAuth.dashboard_path(nil) == ~p"/dashboard"
    end
  end

  describe "signed_in_path/1 dual-role precedence" do
    test "provider takes precedence over staff for dual-role users" do
      user = %Accounts.User{intended_roles: [:staff_provider, :provider]}
      assert UserAuth.signed_in_path(user) == ~p"/provider/dashboard"
    end

    test "staff-only users still go to staff dashboard" do
      user = %Accounts.User{intended_roles: [:staff_provider]}
      assert UserAuth.signed_in_path(user) == ~p"/staff/dashboard"
    end

    test "provider-only users go to provider dashboard" do
      user = %Accounts.User{intended_roles: [:provider]}
      assert UserAuth.signed_in_path(user) == ~p"/provider/dashboard"
    end
  end

  describe "dashboard_path/1 dual-role precedence" do
    test "provider takes precedence over staff for dual-role users" do
      user = %Accounts.User{intended_roles: [:staff_provider, :provider]}
      assert UserAuth.dashboard_path(user) == ~p"/provider/dashboard"
    end

    test "staff-only users still go to staff dashboard" do
      user = %Accounts.User{intended_roles: [:staff_provider]}
      assert UserAuth.dashboard_path(user) == ~p"/staff/dashboard"
    end
  end
end
