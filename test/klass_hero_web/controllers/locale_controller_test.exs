defmodule KlassHeroWeb.LocaleControllerTest do
  @moduledoc """
  The single write path for "change my language".

  A LiveView cannot set cookies, so before this controller existed the settings
  toggle wrote the database and its own socket but never the session — and
  `SetLocale` reads the session ahead of the database preference. The chosen
  language therefore vanished on the next page load (#1161).

  Going through a controller also means the response is a redirect, i.e. a dead
  render, which is the only thing that can refresh `<html lang>`.
  """
  use KlassHeroWeb.ConnCase, async: true
  use Mimic

  import KlassHero.AccountsFixtures
  import KlassHeroWeb.I18nHelpers, only: [get_translation: 2]

  alias KlassHero.Repo

  describe "update/2 session handling" do
    for locale <- KlassHeroWeb.Locale.supported() do
      test "stores #{locale} in the session", %{conn: conn} do
        conn = get(conn, ~p"/locale/#{unquote(locale)}")

        assert get_session(conn, :locale) == unquote(locale)
      end
    end

    test "coerces an unsupported locale to the default rather than storing it", %{conn: conn} do
      conn = get(conn, ~p"/locale/#{KlassHeroWeb.I18nHelpers.unsupported_locale()}")

      assert get_session(conn, :locale) == KlassHeroWeb.Locale.default()
    end

    test "an anonymous visitor can switch language without an account", %{conn: conn} do
      conn = get(conn, ~p"/locale/de")

      assert get_session(conn, :locale) == "de"
      assert redirected_to(conn) == "/"
    end
  end

  describe "update/2 preference persistence" do
    setup do
      %{user: user_fixture()}
    end

    test "persists the choice to the signed-in user's profile", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> get(~p"/locale/de")

      assert Repo.reload!(user).locale == "de"
      assert get_session(conn, :locale) == "de"
    end

    # The path segment lands in conn.params before the :browser pipeline runs, so
    # SetLocale has already switched the process locale by the time the flash is
    # built — the confirmation arrives in the language just chosen, not the old one.
    for locale <- KlassHeroWeb.Locale.supported() do
      test "confirms the change in the newly chosen language (#{locale})", %{conn: conn, user: user} do
        conn = conn |> log_in_user(user) |> get(~p"/locale/#{unquote(locale)}")

        assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
                 get_translation("Language preference updated successfully.", unquote(locale))
      end
    end

    test "does not flash for an anonymous visitor, whose choice is session-only", %{conn: conn} do
      conn = get(conn, ~p"/locale/de")

      refute Phoenix.Flash.get(conn.assigns.flash, :info)
    end

    # Session and stored preference have to agree. SetLocale writes the requested
    # locale to the session from the path param before the controller runs, so a
    # failed persist must put the stored preference back — otherwise the rendered
    # language switches while the flash says it failed and the settings radio,
    # which reads that preference, still shows the old one.
    test "restores the stored preference when the change cannot be persisted", %{conn: conn, user: user} do
      changeset = KlassHero.Accounts.change_user_locale(user, %{locale: "de"})

      expect(KlassHero.Accounts, :update_user_locale, fn _user, _attrs -> {:error, changeset} end)

      conn = conn |> log_in_user(user) |> get(~p"/locale/de")

      assert get_session(conn, :locale) == user.locale
      assert Phoenix.Flash.get(conn.assigns.flash, :error)
      assert Repo.reload!(user).locale == user.locale
    end
  end

  describe "update/2 return_to handling" do
    test "returns the visitor to the page they switched from", %{conn: conn} do
      conn = get(conn, ~p"/locale/de?return_to=/programs")

      assert redirected_to(conn) == "/programs"
    end

    # An unguarded return_to turns the switcher into an open redirect: a crafted
    # link would bounce the visitor off-site while looking like a klass-hero URL.
    @unsafe [
      {"//evil.com", "protocol-relative URL"},
      {"https://evil.com", "absolute URL"},
      {"/\\evil.com", "backslash-smuggled host"},
      {"evil.com", "schemeless host"},
      {"", "empty path"}
    ]

    for {path, description} <- @unsafe do
      test "rejects a #{description} and falls back to the home page", %{conn: conn} do
        conn = get(conn, ~p"/locale/de?return_to=#{unquote(path)}")

        assert redirected_to(conn) == "/",
               "#{unquote(path)} was accepted as a redirect target — open redirect"
      end
    end
  end
end
