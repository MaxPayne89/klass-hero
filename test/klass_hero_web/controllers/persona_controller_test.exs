defmodule KlassHeroWeb.PersonaControllerTest do
  @moduledoc """
  The single write path for "switch which surface I'm looking at".

  It is a controller for the same reason `LocaleController` is: a LiveView
  cannot write `Plug.Session`, so a switch made from the account menu would
  update the socket and the database but leave the session stale, and the choice
  would vanish on the next request (#1161).

  The switch is also an authorization boundary, which locale is not. A stored
  persona is a preference and can never confer one, so the requested persona is
  checked against a freshly resolved `Scope` before anything is written.
  """
  use KlassHeroWeb.ConnCase, async: true

  import KlassHero.AccountsFixtures

  alias KlassHero.Accounts
  alias KlassHero.Family
  alias KlassHero.Provider
  alias KlassHero.Repo

  defp dual_persona_user(_context) do
    user = user_fixture(intended_roles: [:parent, :provider])
    {:ok, _parent} = Family.create_parent_profile(%{identity_id: user.id})

    {:ok, _provider} =
      Provider.create_provider_profile(%{identity_id: user.id, business_name: "Test Business"})

    %{user: user}
  end

  describe "switch/2 for a persona the user holds" do
    setup [:dual_persona_user]

    test "remembers the persona and lands on its dashboard", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> post(~p"/users/persona/parent")

      assert redirected_to(conn) == ~p"/dashboard"
      assert get_session(conn, :active_persona) == :parent
      assert Repo.reload!(user).active_persona == :parent
    end

    test "switches back again", %{conn: conn, user: user} do
      {:ok, user} = Accounts.update_user_active_persona(user, %{active_persona: :parent})

      conn = conn |> log_in_user(user) |> post(~p"/users/persona/provider")

      assert redirected_to(conn) == ~p"/provider/dashboard"
      assert get_session(conn, :active_persona) == :provider
      assert Repo.reload!(user).active_persona == :provider
    end
  end

  describe "switch/2 for a persona the user does not hold" do
    setup [:dual_persona_user]

    # The authorization case locale has no equivalent of. A crafted POST must not
    # be able to store a persona the person never earned, because the switcher
    # renders from the stored value and would otherwise offer a surface whose
    # on_mount guard then bounces them — a loop with no explanation.
    test "refuses to store it and leaves the preference untouched", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> post(~p"/users/persona/staff")

      assert Phoenix.Flash.get(conn.assigns.flash, :error)
      refute get_session(conn, :active_persona) == :staff
      assert Repo.reload!(user).active_persona == nil
    end

    test "refuses an unknown persona rather than raising", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> post(~p"/users/persona/wizard")

      assert Phoenix.Flash.get(conn.assigns.flash, :error)
      assert Repo.reload!(user).active_persona == nil
    end
  end

  describe "switch/2 return_to handling" do
    setup [:dual_persona_user]

    test "returns the user to the page they switched from", %{conn: conn, user: user} do
      conn =
        conn |> log_in_user(user) |> post(~p"/users/persona/parent?return_to=/users/settings")

      assert redirected_to(conn) == "/users/settings"
    end

    # An unguarded return_to turns the switcher into an open redirect: a crafted
    # link would bounce the user off-site while looking like a persona switch.
    @unsafe [
      {"//evil.com", "protocol-relative URL"},
      {"https://evil.com", "absolute URL"},
      {"/\\evil.com", "backslash-smuggled host"},
      {"evil.com", "schemeless host"},
      {"", "empty path"}
    ]

    for {path, description} <- @unsafe do
      test "rejects a #{description} and falls back to the persona dashboard", %{
        conn: conn,
        user: user
      } do
        conn =
          conn
          |> log_in_user(user)
          |> post(~p"/users/persona/parent?return_to=#{unquote(path)}")

        assert redirected_to(conn) == ~p"/dashboard",
               "#{unquote(path)} was accepted as a redirect target — open redirect"
      end
    end
  end

  describe "switch/2 without a session" do
    test "requires an authenticated user", %{conn: conn} do
      conn = post(conn, ~p"/users/persona/parent")

      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end
end
