defmodule KlassHeroWeb.Plugs.SetLocale do
  @moduledoc """
  Plug for detecting and setting the user's locale preference.

  Locale is determined by priority:
  1. Query parameter `?locale=de` (for testing/sharing)
  2. Session stored locale
  3. Authenticated user's database preference
  4. Browser Accept-Language header
  5. Default: "en"

  The locale is stored in session and assigned to conn for use by LiveView hooks.

  Because the session outranks the stored preference and only the plug pipeline
  can write a session, a durable language change must go through
  `KlassHeroWeb.LocaleController` — a LiveView writing the preference alone
  leaves the session stale and the change is lost on the next request (#1161).
  """

  @behaviour Plug

  import Plug.Conn

  alias KlassHeroWeb.Locale

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    locale = detect_locale(conn)

    Gettext.put_locale(KlassHeroWeb.Gettext, locale)

    conn
    |> assign(:locale, locale)
    # Path only, no query string: the root layout builds canonical and hreflang
    # URLs from it, and folding filter params in would mint a separate canonical
    # for every permutation of /programs?category=…
    |> assign(:current_path, conn.request_path)
    |> put_session(:locale, locale)
  end

  defp detect_locale(conn) do
    [
      &query_param_locale/1,
      &session_locale/1,
      &user_locale/1,
      &accept_language_locale/1,
      fn _ -> Locale.default() end
    ]
    |> Enum.find_value(fn detector -> detector.(conn) end)
    |> Locale.validate()
  end

  defp query_param_locale(%{params: %{"locale" => locale}}), do: locale
  defp query_param_locale(_conn), do: nil

  defp session_locale(conn), do: get_session(conn, :locale)

  defp user_locale(conn) do
    case conn.assigns[:current_scope] do
      %{user: %{locale: locale}} when is_binary(locale) -> locale
      _ -> nil
    end
  end

  defp accept_language_locale(conn) do
    conn
    |> get_req_header("accept-language")
    |> List.first()
    |> parse_accept_language()
  end

  defp parse_accept_language(nil), do: nil

  defp parse_accept_language(header) do
    header
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&extract_language_code/1)
    |> Enum.find(&Locale.supported?/1)
  end

  defp extract_language_code(lang_entry) do
    lang_entry
    |> String.split(";")
    |> List.first()
    |> String.split("-")
    |> List.first()
    |> String.downcase()
  end
end
