defmodule KlassHeroWeb.UserAuth do
  @moduledoc """
  Provides authentication plugs and helpers for user sessions.

  This module handles user authentication, session management, and
  route protection through Phoenix plugs. It manages session tokens,
  remember-me cookies, and provides hooks for LiveView authentication.
  """

  use KlassHeroWeb, :verified_routes
  use Gettext, backend: KlassHeroWeb.Gettext

  import Phoenix.Controller
  import Plug.Conn

  alias KlassHero.Accounts
  alias KlassHero.Accounts.Scope
  alias KlassHero.Messaging
  alias KlassHeroWeb.RoleRouting

  # Make the remember me cookie valid for 14 days. This should match
  # the session validity setting in UserToken.
  @max_cookie_age_in_days 14
  @remember_me_cookie "_klass_hero_web_user_remember_me"
  @remember_me_options [
    sign: true,
    max_age: @max_cookie_age_in_days * 24 * 60 * 60,
    same_site: "Lax"
  ]

  # How old the session token should be before a new one is issued. When a request is made
  # with a session token older than this value, then a new session token will be created
  # and the session and remember-me cookies (if set) will be updated with the new token.
  # Lowering this value will result in more tokens being created by active users. Increasing
  # it will result in less time before a session token expires for a user to get issued a new
  # token. This can be set to a value greater than `@max_cookie_age_in_days` to disable
  # the reissuing of tokens completely.
  @session_reissue_age_in_days 7

  @doc """
  Logs the user in.

  Redirects to the session's `:user_return_to` path
  or falls back to the `signed_in_path/1`.
  """
  def log_in_user(conn, user, params \\ %{}) do
    user_return_to = get_session(conn, :user_return_to)

    conn
    |> create_or_extend_session(user, params)
    |> redirect(to: user_return_to || signed_in_path(user))
  end

  @doc """
  Logs the user out.

  It clears all session data for safety. See renew_session.
  """
  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      KlassHeroWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session(nil)
    |> delete_resp_cookie(@remember_me_cookie)
    |> redirect(to: ~p"/")
  end

  @doc """
  Authenticates the user by looking into the session and remember me token.

  Will reissue the session token if it is older than the configured age.
  """
  def fetch_current_scope_for_user(conn, _opts) do
    with {token, conn} <- ensure_user_token(conn),
         {user, token_inserted_at} <- Accounts.get_user_by_session_token(token) do
      conn
      |> assign(:current_scope, Scope.for_user(user))
      |> maybe_reissue_user_session_token(user, token_inserted_at)
    else
      nil -> assign(conn, :current_scope, Scope.for_user(nil))
    end
  end

  defp ensure_user_token(conn) do
    if token = get_session(conn, :user_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if token = conn.cookies[@remember_me_cookie] do
        {token, conn |> put_token_in_session(token) |> put_session(:user_remember_me, true)}
      end
    end
  end

  # Reissue the session token if it is older than the configured reissue age.
  defp maybe_reissue_user_session_token(conn, user, token_inserted_at) do
    token_age = DateTime.diff(DateTime.utc_now(:second), token_inserted_at, :day)

    if token_age >= @session_reissue_age_in_days do
      create_or_extend_session(conn, user, %{})
    else
      conn
    end
  end

  # This function is the one responsible for creating session tokens
  # and storing them safely in the session and cookies. It may be called
  # either when logging in, during sudo mode, or to renew a session which
  # will soon expire.
  #
  # When the session is created, rather than extended, the renew_session
  # function will clear the session to avoid fixation attacks. See the
  # renew_session function to customize this behaviour.
  defp create_or_extend_session(conn, user, params) do
    token = Accounts.generate_user_session_token(user)
    remember_me = get_session(conn, :user_remember_me)

    conn
    |> renew_session(user)
    |> put_token_in_session(token)
    |> maybe_write_remember_me_cookie(token, params, remember_me)
  end

  # Do not renew session if the user is already logged in
  # to prevent CSRF errors or data being lost in tabs that are still open
  defp renew_session(conn, user) when conn.assigns.current_scope.user.id == user.id do
    conn
  end

  # This function renews the session ID and erases the whole
  # session to avoid fixation attacks. If there is any data
  # in the session you may want to preserve after log in/log out,
  # you must explicitly fetch the session data before clearing
  # and then immediately set it after clearing, for example:
  #
  #     defp renew_session(conn, _user) do
  #       delete_csrf_token()
  #       preferred_locale = get_session(conn, :preferred_locale)
  #
  #       conn
  #       |> configure_session(renew: true)
  #       |> clear_session()
  #       |> put_session(:preferred_locale, preferred_locale)
  #     end
  #
  defp renew_session(conn, _user) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}, _),
    do: write_remember_me_cookie(conn, token)

  defp maybe_write_remember_me_cookie(conn, token, _params, true), do: write_remember_me_cookie(conn, token)

  defp maybe_write_remember_me_cookie(conn, _token, _params, _), do: conn

  defp write_remember_me_cookie(conn, token) do
    conn
    |> put_session(:user_remember_me, true)
    |> put_resp_cookie(@remember_me_cookie, token, @remember_me_options)
  end

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, user_session_topic(token))
  end

  @doc """
  Disconnects existing sockets for the given tokens.
  """
  def disconnect_sessions(tokens) do
    Enum.each(tokens, fn %{token: token} ->
      KlassHeroWeb.Endpoint.broadcast(user_session_topic(token), "disconnect", %{})
    end)
  end

  defp user_session_topic(token), do: "users_sessions:#{Base.url_encode64(token)}"

  @doc """
  Handles mounting and authenticating the current_scope in LiveViews.

  ## `on_mount` arguments

    * `:mount_current_scope` - Assigns current_scope
      to socket assigns based on user_token, or nil if
      there's no user_token or no matching user.

    * `:require_authenticated` - Authenticates the user from the session,
      and assigns the current_scope to socket assigns based
      on user_token.
      Redirects to login page if there's no logged user.

    * `:require_admin` - Requires the user to have `is_admin: true`.
      Redirects to home page with error flash if the user is not an admin.
      Use this hook for admin-only routes (verification, moderation).

    * `:redirect_provider_or_staff_from_parent_routes` - Redirects users with
      a provider or staff profile away from parent-specific routes to their
      role's dashboard. Staff takes precedence over provider.

  ## Examples

  Use the `on_mount` lifecycle macro in LiveViews to mount or authenticate
  the `current_scope`:

      defmodule KlassHeroWeb.PageLive do
        use KlassHeroWeb, :live_view

        on_mount {KlassHeroWeb.UserAuth, :mount_current_scope}
        ...
      end

  Or use the `live_session` of your router to invoke the on_mount callback:

      live_session :authenticated, on_mount: [{KlassHeroWeb.UserAuth, :require_authenticated}] do
        live "/profile", ProfileLive, :index
      end
  """
  def on_mount(:mount_current_scope, _params, session, socket) do
    {:cont, mount_current_scope(socket, session)}
  end

  def on_mount(:fetch_unread_count, _params, _session, socket) do
    if socket.assigns[:current_scope] && socket.assigns.current_scope.user do
      user_id = socket.assigns.current_scope.user.id
      count = Messaging.get_total_unread_count(user_id)
      {:cont, Phoenix.Component.assign(socket, :total_unread_count, count)}
    else
      {:cont, Phoenix.Component.assign(socket, :total_unread_count, 0)}
    end
  end

  def on_mount(:require_authenticated, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if socket.assigns.current_scope && socket.assigns.current_scope.user do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, gettext("You must log in to access this page."))
        |> Phoenix.LiveView.redirect(to: ~p"/users/log-in")

      {:halt, socket}
    end
  end

  def on_mount(:require_sudo_mode, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if Accounts.sudo_mode?(socket.assigns.current_scope.user, -10) do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(
          :error,
          gettext("You must re-authenticate to access this page.")
        )
        |> Phoenix.LiveView.redirect(to: ~p"/users/log-in")

      {:halt, socket}
    end
  end

  def on_mount(:require_parent, _params, session, socket) do
    require_role(
      socket,
      session,
      &Scope.parent?/1,
      gettext("You must have a parent profile to access this page.")
    )
  end

  def on_mount(:require_provider, _params, session, socket) do
    require_role(
      socket,
      session,
      &Scope.provider?/1,
      gettext("You must have a provider profile to access this page.")
    )
  end

  def on_mount(:require_staff, _params, session, socket) do
    require_role(
      socket,
      session,
      &Scope.staff?/1,
      gettext("You must be a staff member to access this page.")
    )
  end

  # Requires the user to be an admin.
  # Trigger: user attempts to access admin-only routes
  # Why: admin routes contain sensitive verification/moderation functionality
  # Outcome: non-admin users redirected to home with error flash
  def on_mount(:require_admin, _params, _session, socket) do
    case socket.assigns[:current_scope] do
      %{user: %{is_admin: true}} ->
        {:cont, socket}

      _ ->
        {:halt,
         socket
         |> Phoenix.LiveView.put_flash(:error, gettext("You don't have access to that page."))
         |> Phoenix.LiveView.redirect(to: ~p"/")}
    end
  end

  # Redirects users with a provider or staff profile to their role's dashboard.
  # Provider takes precedence over staff. Parent-only users pass through.
  def on_mount(:redirect_provider_or_staff_from_parent_routes, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if socket.assigns.current_scope && socket.assigns.current_scope.user do
      scope = Scope.resolve_roles(socket.assigns.current_scope)
      socket = Phoenix.Component.assign(socket, :current_scope, scope)

      case RoleRouting.primary_role(scope.roles) do
        role when role in [:provider, :staff] ->
          {:halt, Phoenix.LiveView.redirect(socket, to: RoleRouting.dashboard_path(scope.roles))}

        _ ->
          {:cont, socket}
      end
    else
      {:cont, socket}
    end
  end

  # Helper to require a specific role with role resolution
  defp require_role(socket, session, role_check_fn, error_message) do
    socket = mount_current_scope(socket, session)

    if socket.assigns.current_scope && socket.assigns.current_scope.user do
      # Resolve roles to populate parent/provider fields
      scope = Scope.resolve_roles(socket.assigns.current_scope)
      socket = Phoenix.Component.assign(socket, :current_scope, scope)

      if role_check_fn.(scope) do
        {:cont, socket}
      else
        socket =
          socket
          |> Phoenix.LiveView.put_flash(:error, error_message)
          |> Phoenix.LiveView.redirect(to: ~p"/")

        {:halt, socket}
      end
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(
          :error,
          gettext("You must be authenticated to access this page.")
        )
        |> Phoenix.LiveView.redirect(to: ~p"/")

      {:halt, socket}
    end
  end

  defp mount_current_scope(socket, session) do
    Phoenix.Component.assign_new(socket, :current_scope, fn ->
      {user, _} =
        if user_token = session["user_token"] do
          Accounts.get_user_by_session_token(user_token)
        end || {nil, nil}

      Scope.for_user(user)
    end)
  end

  @doc "Returns the path to redirect to after log in, based on the user's intended roles."
  def signed_in_path(%Accounts.User{intended_roles: roles}), do: RoleRouting.dashboard_path(roles)

  def signed_in_path(_), do: ~p"/"

  @doc "Returns the correct dashboard path based on the user's intended roles."
  def dashboard_path(%Accounts.User{intended_roles: roles}), do: RoleRouting.dashboard_path(roles)

  def dashboard_path(nil), do: ~p"/dashboard"

  @doc """
  Plug for routes that require the user to be authenticated.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns.current_scope && conn.assigns.current_scope.user do
      conn
    else
      conn
      |> put_flash(:error, gettext("You must log in to access this page."))
      |> maybe_store_return_to()
      |> redirect(to: ~p"/users/log-in")
      |> halt()
    end
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn
end
