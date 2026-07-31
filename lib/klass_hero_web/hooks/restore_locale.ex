defmodule KlassHeroWeb.Hooks.RestoreLocale do
  @moduledoc """
  LiveView on_mount hook to restore locale in each LiveView process.

  LiveViews run in isolated processes, so `Gettext.get_locale()` must be
  set for each process. This hook restores the locale from session and
  assigns it to the socket for use in templates.

  ## Usage

  Add to live_session in router:

      live_session :main,
        on_mount: [{KlassHeroWeb.Hooks.RestoreLocale, :restore_locale}] do
        # routes...
      end

  Then access `@locale` in templates for language-aware rendering.
  """

  import Phoenix.Component

  alias KlassHeroWeb.Locale

  def on_mount(:restore_locale, _params, session, socket) do
    locale = determine_locale(session, socket)

    Gettext.put_locale(KlassHeroWeb.Gettext, locale)

    {:cont, assign(socket, :locale, locale)}
  end

  defp determine_locale(session, socket) do
    session
    |> preferred_locale(socket)
    |> Locale.validate()
  end

  defp preferred_locale(session, socket) do
    cond do
      # 1. Session locale (set by plug - includes query param for explicit user choice)
      session_locale = Map.get(session, "locale") ->
        session_locale

      # 2. Fall back to authenticated user preference
      user_locale = get_user_locale(socket) ->
        user_locale

      # 3. Default
      true ->
        Locale.default()
    end
  end

  defp get_user_locale(socket) do
    case socket.assigns do
      %{current_scope: %{user: %{locale: locale}}} when is_binary(locale) -> locale
      _ -> nil
    end
  end
end
