defmodule KlassHeroWeb.PersonaController do
  @moduledoc """
  The one place a persona switch is written.

  A LiveView cannot write `Plug.Session`, so it can never make the switch stick:
  the socket and the column would update while the session kept the old value,
  and the choice would vanish on the next request. That is the locale bug
  (#1161) in a different costume, and it is why this is a controller answering
  with a redirect — a dead render, which is also what re-runs every `on_mount`
  so the new surface's chrome and guards apply immediately.

  The session is the choice for this browsing session; the stored column is the
  durable default that seeds it after `clear_session/1` at login.

  Unlike a locale, a persona is an authorization-adjacent concept, so the
  requested one is checked against a freshly resolved `Scope` before anything is
  written. A stored persona is a preference and must never be able to confer one
  (ADR-0005) — and storing a persona the person does not hold would render a
  switcher entry whose destination immediately bounces them back.
  """
  use KlassHeroWeb, :controller

  alias KlassHero.Accounts
  alias KlassHero.Accounts.Scope
  alias KlassHeroWeb.Persona

  def switch(conn, %{"persona" => requested} = params) do
    scope = Scope.resolve_roles(conn.assigns.current_scope)
    persona = Persona.validate(requested)

    if persona in Persona.available(scope) do
      apply_persona(conn, scope, persona, params)
    else
      conn
      |> put_flash(:error, gettext("You don't have that profile."))
      |> redirect(to: Persona.path(Persona.resolve(scope), :dashboard))
    end
  end

  defp apply_persona(conn, scope, persona, params) do
    case Accounts.update_user_active_persona(scope.user, %{active_persona: persona}) do
      {:ok, _user} ->
        conn
        |> put_session(:active_persona, persona)
        |> redirect(to: return_to(params, persona))

      # The session is deliberately left alone here. Writing it on a failed
      # persist would switch the chrome while the flash said it failed, and the
      # next login would silently switch back — the same split-brain the locale
      # controller guards against.
      {:error, _changeset} ->
        conn
        |> put_flash(:error, gettext("Could not switch profile."))
        |> redirect(to: Persona.path(Persona.resolve(scope), :dashboard))
    end
  end

  defp return_to(%{"return_to" => path}, persona) when is_binary(path) do
    if local_path?(path), do: path, else: Persona.path(persona, :dashboard)
  end

  defp return_to(_params, persona), do: Persona.path(persona, :dashboard)

  # Only a single-slash-prefixed path is ours. "//evil.com" is a protocol-relative
  # URL and "/\evil.com" is treated as one by browsers, so both would send the
  # user off-site from a link that looks like a profile switch.
  defp local_path?("//" <> _rest), do: false
  defp local_path?("/\\" <> _rest), do: false
  defp local_path?("/" <> _rest), do: true
  defp local_path?(_path), do: false
end
