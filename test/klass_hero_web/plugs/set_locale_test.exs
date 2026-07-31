defmodule KlassHeroWeb.Plugs.SetLocaleTest do
  @moduledoc """
  The precedence chain that decides a request's language.

  The order is load-bearing rather than arbitrary: the **session** is this
  browsing session's choice (the `?locale=` pill), and the **stored preference**
  is the durable default that seeds it after `clear_session/1` at login. Because
  the session outranks the preference and only the plug pipeline can write a
  session, a locale change has to go through `LocaleController` — writing it from
  a LiveView leaves the session stale and the change evaporates (#1161).

  This plug had no tests at all before that bug.
  """
  use KlassHeroWeb.ConnCase, async: true

  alias KlassHeroWeb.Plugs.SetLocale

  describe "precedence" do
    # {description, param, session, stored preference, accept-language, expected}
    @precedence [
      {"the query param outranks everything", "de", "en", "en", "en-GB", "de"},
      {"the session outranks the stored preference", nil, "de", "en", "en-GB", "de"},
      {"the stored preference outranks the browser", nil, nil, "de", "en-GB", "de"},
      {"the browser is consulted last", nil, nil, nil, "de-DE,de;q=0.9,en;q=0.8", "de"},
      {"an unsupported browser language falls back", nil, nil, nil, "fr-FR,fr;q=0.9", "en"},
      {"nothing at all falls back", nil, nil, nil, nil, "en"},
      # An explicit but unsupported request resets to the default rather than
      # falling through to the session — asking for a language we don't have is
      # a clearer signal than the session it replaces.
      {"an unsupported query param outranks a valid session", "fr", "de", nil, nil, "en"}
    ]

    for {description, param, session, preference, accept_language, expected} <- @precedence do
      test description do
        conn =
          call(
            param: unquote(param),
            session: unquote(session),
            preference: unquote(preference),
            accept_language: unquote(accept_language)
          )

        assert conn.assigns.locale == unquote(expected)
      end
    end
  end

  describe "what the plug leaves behind" do
    test "persists the resolved locale so the next request agrees with this one" do
      conn = call(param: "de")

      assert get_session(conn, :locale) == "de"
    end

    test "assigns the request path for the root layout's canonical and hreflang tags" do
      conn = call(path: "/programs", param: "de")

      assert conn.assigns.current_path == "/programs"
    end

    test "the assigned path excludes the query string" do
      conn = call(path: "/programs", param: "de")

      refute conn.assigns.current_path =~ "locale"
    end
  end

  defp call(opts) do
    path = Keyword.get(opts, :path, "/")
    query = if opts[:param], do: "?locale=#{opts[:param]}", else: ""

    :get
    |> build_conn(path <> query)
    |> Plug.Conn.fetch_query_params()
    |> Plug.Test.init_test_session(session_for(opts[:session]))
    |> put_accept_language(opts[:accept_language])
    |> put_preference(opts[:preference])
    |> SetLocale.call([])
  end

  defp session_for(nil), do: %{}
  defp session_for(locale), do: %{locale: locale}

  defp put_accept_language(conn, nil), do: conn
  defp put_accept_language(conn, header), do: put_req_header(conn, "accept-language", header)

  defp put_preference(conn, nil), do: conn
  defp put_preference(conn, locale), do: assign(conn, :current_scope, %{user: %{locale: locale}})
end
