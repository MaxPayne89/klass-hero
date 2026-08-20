defmodule KlassHeroWeb.Hooks.RestorePersona do
  @moduledoc """
  Restores the active persona into each LiveView, for the chrome to render from.

  Mirrors `KlassHeroWeb.Hooks.RestoreLocale` and runs in the same position —
  last in the `on_mount` list, after whichever hook resolved the scope.

  ## It never queries

  `available/1` and `resolve/1` need a *resolved* `Scope`, and by the time this
  runs one hook already produced one: `:redirect_provider_or_staff_from_parent_routes`
  on the parent surface, `require_role/4` on the provider and staff surfaces,
  and `:resolve_personas` on account settings, which has no role gate of its own.
  Resolving a second time here would double the persona queries on every mount,
  so this hook deliberately assumes the work is done. A live_session that wires
  it without one of those hooks will render an empty switcher rather than a
  wrong one.

  ## The session key is a string

  The write side uses the atom `:active_persona` (`PersonaController`), but a
  LiveView session is string-keyed, so it is read back as `"active_persona"`.
  The same asymmetry exists for locale and is easy to get wrong in both
  directions.

  The session is only a fast path. It agrees with `users.active_persona` except
  in the window right after login, where `clear_session/1` has emptied it and
  the column is the durable default that seeds it — so the scope, not the
  session, has the last word.
  """

  import Phoenix.Component

  alias KlassHero.Accounts.Scope
  alias KlassHeroWeb.Persona

  def on_mount(:restore_persona, _params, session, socket) do
    scope = socket.assigns[:current_scope]

    {:cont,
     socket
     |> assign(:active_persona, active_persona(session, scope))
     |> assign(:personas, available(scope))}
  end

  defp active_persona(session, %Scope{user: user} = scope) when not is_nil(user) do
    from_session = Persona.validate(session["active_persona"])

    if from_session in Persona.available(scope) do
      from_session
    else
      Persona.resolve(scope)
    end
  end

  defp active_persona(_session, _scope), do: nil

  defp available(%Scope{user: user} = scope) when not is_nil(user), do: Persona.available(scope)
  defp available(_scope), do: []
end
