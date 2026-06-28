defmodule KlassHeroWeb.I18nHelpers do
  @moduledoc """
  Helper functions for testing internationalization (i18n) and localization.

  Provides utilities for:
  - Setting locale in tests
  - Asserting translations
  - Creating users with locale preferences
  - Viewport dimension helpers for responsive testing
  """

  import ExUnit.Assertions
  import Phoenix.LiveViewTest

  alias KlassHero.Accounts
  alias KlassHero.Accounts.User
  alias KlassHero.AccountsFixtures
  alias KlassHero.Repo
  alias Phoenix.LiveViewTest.View

  @doc """
  Adds locale query parameter to a path.

  ## Examples

      path = add_locale_param("/dashboard", "de")  # => "/dashboard?locale=de"
  """
  def add_locale_param(path, locale) when is_binary(path) do
    separator = if String.contains?(path, "?"), do: "&", else: "?"
    "#{path}#{separator}locale=#{locale}"
  end

  @doc """
  Gets the translation for a given key and locale from the Gettext backend.

  ## Examples

      assert get_translation("Today", "de") == "Heute"
      assert get_translation("Progress", "en") == "Progress"
  """
  def get_translation(msgid, locale) do
    # Temporarily set the locale to retrieve the translation
    previous_locale = Gettext.get_locale(KlassHeroWeb.Gettext)
    Gettext.put_locale(KlassHeroWeb.Gettext, locale)

    translation = Gettext.dgettext(KlassHeroWeb.Gettext, "default", msgid)

    # Restore previous locale
    Gettext.put_locale(KlassHeroWeb.Gettext, previous_locale)

    translation
  end

  @doc """
  Asserts that a LiveView contains the expected translation for a given key.

  Handles HTML-encoded characters (e.g., `&` becomes `&amp;` in HTML).

  ## Examples

      assert_translation(view, "Today", "de")  # Expects "Heute" in view
      assert_translation(view, "Progress", "en")  # Expects "Progress" in view
      assert_translation(view, "Account & Profile", "de")  # Handles HTML encoding
  """
  def assert_translation(view, msgid, locale) do
    expected = get_translation(msgid, locale)
    html = render(view)

    # Check for both raw and HTML-encoded versions
    expected_encoded = Phoenix.HTML.html_escape(expected) |> Phoenix.HTML.safe_to_string()
    found = html =~ expected || html =~ expected_encoded

    assert found,
           """
           Expected translation not found in view.

           Key: #{inspect(msgid)}
           Locale: #{locale}
           Expected: #{inspect(expected)}
           Expected (HTML-encoded): #{inspect(expected_encoded)}

           Rendered HTML (first 500 chars):
           #{String.slice(html, 0, 500)}
           """
  end

  @doc """
  Asserts that a rendered HTML string contains the expected translation.

  Handles HTML-encoded characters (e.g., `&` becomes `&amp;` in HTML).

  ## Examples

      assert_translation_in_html(html, "Today", "de")  # Expects "Heute" in HTML
      assert_translation_in_html(html, "Account & Profile", "de")  # Handles HTML encoding
  """
  def assert_translation_in_html(html, msgid, locale) do
    expected = get_translation(msgid, locale)

    # Check for both raw and HTML-encoded versions
    expected_encoded = Phoenix.HTML.html_escape(expected) |> Phoenix.HTML.safe_to_string()
    found = html =~ expected || html =~ expected_encoded

    assert found,
           """
           Expected translation not found in HTML.

           Key: #{inspect(msgid)}
           Locale: #{locale}
           Expected: #{inspect(expected)}
           Expected (HTML-encoded): #{inspect(expected_encoded)}

           Rendered HTML (first 500 chars):
           #{String.slice(html, 0, 500)}
           """
  end

  @doc """
  Creates a user with a specific locale preference.

  ## Examples

      user = user_with_locale("de")
      assert user.locale == "de"
  """
  def user_with_locale(locale, attrs \\ %{}) do
    user = AccountsFixtures.user_fixture(attrs)

    # Update user locale preference
    {:ok, user} =
      user
      |> Accounts.User.locale_changeset(%{locale: locale})
      |> Repo.update()

    user
  end

  @doc """
  Asserts that a flash message in a LiveView matches the expected translation.

  ## Examples

      assert_flash_translation(view, :info, "User updated successfully", "de")
      assert_flash_translation(view, :error, "Invalid credentials", "en")
  """
  def assert_flash_translation(view, kind, msgid, locale) do
    flash = :sys.get_state(view.pid).socket.assigns.flash
    actual = Phoenix.Flash.get(flash, kind)
    expected = get_translation(msgid, locale)

    assert actual == expected,
           """
           Flash message translation mismatch.

           Kind: #{inspect(kind)}
           Key: #{inspect(msgid)}
           Locale: #{locale}
           Expected: #{inspect(expected)}
           Actual: #{inspect(actual)}
           """
  end

  @doc """
  Returns viewport dimensions for responsive testing.

  ## Examples

      {width, height} = viewport_size(:mobile)  # => {375, 667}
      {width, height} = viewport_size(:tablet)  # => {768, 1024}
      {width, height} = viewport_size(:desktop) # => {1440, 900}
  """
  def viewport_size(:mobile), do: {375, 667}
  def viewport_size(:tablet), do: {768, 1024}
  def viewport_size(:desktop), do: {1440, 900}

  @doc """
  Asserts that the current locale in the view matches the expected locale.

  ## Examples

      assert_locale(view, "de")
      assert_locale(view, "en")
  """
  def assert_locale(view, expected_locale) do
    actual_locale =
      case view do
        %{assigns: %{locale: locale}} ->
          locale

        %View{} ->
          :sys.get_state(view.pid).socket.assigns[:locale]

        _ ->
          nil
      end

    assert actual_locale == expected_locale,
           """
           Locale mismatch in view.

           Expected: #{inspect(expected_locale)}
           Actual: #{inspect(actual_locale)}
           """
  end

  @doc """
  Sets up a connection with a specific Accept-Language header.

  ## Examples

      conn = with_accept_language(conn, "de-DE,de;q=0.9,en;q=0.8")
  """
  def with_accept_language(conn, accept_language) do
    conn
    |> Plug.Conn.put_req_header("accept-language", accept_language)
  end

  @doc """
  Sets up a connection with a locale for LiveView tests.

  Updates the authenticated user's locale preference in the database since
  the RestoreLocale hook checks user preference FIRST before session locale.

  ## Examples

      {:ok, view, _html} =
        conn
        |> setup_locale_for_navigation("de")
        |> live(~p"/dashboard")
  """
  def setup_locale_for_navigation(conn, locale) do
    # Set Gettext locale for this process
    Gettext.put_locale(KlassHeroWeb.Gettext, locale)

    # Only attempt session-related operations if session is configured
    # Public routes may not have session configuration in tests
    if Map.has_key?(conn.private, :plug_session_fetch) do
      # Ensure session is fetched
      conn = Plug.Conn.fetch_session(conn)

      # Update the authenticated user's locale preference in the database
      # The RestoreLocale hook checks user.locale FIRST, so this is critical
      case Plug.Conn.get_session(conn, :user_token) do
        nil ->
          # No authenticated user, just return conn
          conn

        user_token ->
          {user, _user_token} = Accounts.get_user_by_session_token(user_token)
          update_user_locale(user, locale)
          conn
      end
    else
      # No session configured, just return conn with locale set
      conn
    end
  end

  # Private helper to update user locale in database if user exists
  defp update_user_locale(user, locale) do
    if user && is_struct(user, User) do
      user
      |> Accounts.User.locale_changeset(%{locale: locale})
      |> Repo.update!()
    end
  end

  @doc """
  Returns a list of supported locales for the application.

  ## Examples

      supported_locales() # => ["en", "de"]
  """
  def supported_locales do
    Application.get_env(:klass_hero, KlassHeroWeb.Gettext)[:locales] || ["en", "de"]
  end

  @doc """
  Returns the default locale for the application.

  ## Examples

      default_locale() # => "en"
  """
  def default_locale do
    Application.get_env(:klass_hero, KlassHeroWeb.Gettext)[:default_locale] || "en"
  end
end
