defmodule KlassHeroWeb.RootLayoutI18nTest do
  @moduledoc """
  What the root layout tells the browser about language.

  `<html lang>` drives screen-reader pronunciation, browser translation offers
  and hreflang indexing, so serving German content under `lang="en"` (#1161) is
  wrong on all three at once.

  These assertions can only go red through a DEAD render. `live/2` returns the
  connected re-render with `root.html.heex` stripped, so the same assertion
  there would pass no matter what the layout says — see `site_icons_test.exs`.
  """
  use KlassHeroWeb.ConnCase, async: true

  describe "html lang attribute" do
    for locale <- KlassHeroWeb.Locale.supported() do
      test "declares lang=#{locale} when the request resolves to #{locale}", %{conn: conn} do
        assert lang_of(conn, "/?locale=#{unquote(locale)}") == unquote(locale)
      end
    end

    test "falls back to the default locale for an unsupported one", %{conn: conn} do
      unsupported = KlassHeroWeb.I18nHelpers.unsupported_locale()

      assert lang_of(conn, "/?locale=#{unsupported}") == KlassHeroWeb.Locale.default()
    end

    test "declares a lang on an authenticated route too, not just marketing pages", %{conn: conn} do
      user = KlassHero.AccountsFixtures.user_fixture()

      lang =
        conn
        |> log_in_user(user)
        |> lang_of("/users/settings?locale=de")

      assert lang == "de"
    end
  end

  describe "hreflang and canonical" do
    setup %{conn: conn} do
      %{doc: doc_for(conn, "/programs?locale=de")}
    end

    test "canonical names the explicit-locale URL, not the bare path", %{doc: doc} do
      assert hrefs(doc, ~s(link[rel="canonical"])) == [absolute("/programs?locale=de")]
    end

    # Derived from the supported set, so adding a locale extends this coverage
    # instead of leaving the new one silently unasserted. A bare path serves
    # whatever the visitor's session or Accept-Language says, which is exactly
    # what x-default is for, so it is the one entry that is not a locale.
    @alternates Enum.map(KlassHeroWeb.Locale.supported(), &{&1, "/programs?locale=#{&1}"}) ++
                  [{"x-default", "/programs"}]

    for {hreflang, path} <- @alternates do
      test "declares the #{hreflang} alternate", %{doc: doc} do
        assert hrefs(doc, ~s(link[rel="alternate"][hreflang="#{unquote(hreflang)}"])) ==
                 [absolute(unquote(path))]
      end
    end

    test "every declared URL is absolute — a relative hreflang is ignored", %{doc: doc} do
      urls = hrefs(doc, ~s(link[rel="canonical"])) ++ hrefs(doc, ~s(link[rel="alternate"]))

      # one canonical + one alternate per locale + x-default
      assert length(urls) == length(KlassHeroWeb.Locale.supported()) + 2
      assert Enum.all?(urls, &String.starts_with?(&1, "http")), "found a relative URL in #{inspect(urls)}"
    end

    test "the canonical follows the locale actually served", %{conn: conn} do
      doc = doc_for(conn, "/programs?locale=en")

      assert hrefs(doc, ~s(link[rel="canonical"])) == [absolute("/programs?locale=en")]
    end
  end

  defp absolute(path), do: Application.get_env(:klass_hero, :app_base_url) <> path

  defp hrefs(doc, selector), do: doc |> LazyHTML.query(selector) |> LazyHTML.attribute("href")

  defp doc_for(conn, path) do
    conn
    |> get(path)
    |> html_response(200)
    |> LazyHTML.from_document()
  end

  defp lang_of(conn, path) do
    [lang] =
      conn
      |> get(path)
      |> html_response(200)
      |> LazyHTML.from_document()
      |> LazyHTML.query("html")
      |> LazyHTML.attribute("lang")

    lang
  end
end
