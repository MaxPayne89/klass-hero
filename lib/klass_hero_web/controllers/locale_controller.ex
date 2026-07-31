defmodule KlassHeroWeb.LocaleController do
  @moduledoc """
  The one place a language choice is written.

  A LiveView cannot set cookies, so it can never make a locale change stick:
  `SetLocale` reads the session ahead of the user's stored preference, and only
  a plug-pipeline response can write that session. Routing the change through a
  controller writes both at once and answers with a redirect — a dead render,
  which is also the only thing that can refresh `<html lang>` in the root
  layout.

  The session is the choice for this browsing session; the stored preference is
  the durable default that seeds it after `clear_session/1` at login.
  """
  use KlassHeroWeb, :controller

  alias KlassHero.Accounts
  alias KlassHeroWeb.Locale

  def update(conn, %{"locale" => requested} = params) do
    conn
    |> apply_locale(Locale.validate(requested))
    |> redirect(to: return_to(params))
  end

  defp apply_locale(%{assigns: %{current_scope: %{user: %{} = user}}} = conn, locale) do
    case Accounts.update_user_locale(user, %{locale: locale}) do
      {:ok, _user} ->
        conn
        |> put_session(:locale, locale)
        |> put_flash(:info, gettext("Language preference updated successfully."))

      # SetLocale has already written the requested locale to the session by the
      # time we get here — it reads :locale straight off the path param. So a
      # failed persist has to put the stored preference back, or the rendered
      # language would switch while the flash says it failed and the settings
      # radio, which reads that preference, kept showing the old value.
      {:error, _changeset} ->
        conn
        |> put_session(:locale, Locale.validate(user.locale))
        |> put_flash(:error, gettext("Failed to update language preference."))
    end
  end

  # Anonymous visitors have nowhere durable to store a preference; the session
  # is the whole of their choice, so there is nothing to confirm.
  defp apply_locale(conn, locale), do: put_session(conn, :locale, locale)

  defp return_to(%{"return_to" => path}) when is_binary(path) do
    if local_path?(path), do: path, else: ~p"/"
  end

  defp return_to(_params), do: ~p"/"

  # Only a single-slash-prefixed path is ours. "//evil.com" is a protocol-relative
  # URL and "/\evil.com" is treated as one by browsers, so both would send the
  # visitor off-site from a link that looks like a language switch.
  defp local_path?("//" <> _rest), do: false
  defp local_path?("/\\" <> _rest), do: false
  defp local_path?("/" <> _rest), do: true
  defp local_path?(_path), do: false
end
