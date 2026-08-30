defmodule KlassHeroWeb.Hooks.NavSurface do
  @moduledoc """
  Records which surface a LiveView is being rendered on, so the shared provider
  chrome can offer the right navigation.

  Provider and staff share `provider_app` — same sidebar, same mobile tabs — but
  not the same routes. Before this, the chrome hardcoded the provider's list, so
  a staff-only person was offered six sidebar entries of which one worked, and
  three mobile tabs of which none did; `require_role/4` bounced them to `/` with
  a red flash, and `aria-current="page"` marked the very link that ejected them.

  ## Why the live_session and not the persona

  `@active_persona` is already in layout scope, and reading it here would have
  been fewer moving parts. But a persona is a *preference and never a grant*
  (ADR-0005 amendment, and `KlassHeroWeb.Persona`'s own moduledoc), so it can
  disagree with the page you are actually on — someone holding both personas can
  sit on `/provider/dashboard` with `:staff` selected. The live_session is the
  same fact `require_role/4` enforces, so deriving the nav from it makes an
  offered-but-rejected link structurally impossible rather than merely unlikely.

  Wired per live_session in the router, which is what supplies the surface:

      on_mount: [..., {NavSurface, :provider}]
      on_mount: [..., {NavSurface, :staff}]
  """

  import Phoenix.Component

  @type surface :: :provider | :staff

  def on_mount(surface, _params, _session, socket) when surface in [:provider, :staff] do
    {:cont, assign(socket, :nav_surface, surface)}
  end
end
