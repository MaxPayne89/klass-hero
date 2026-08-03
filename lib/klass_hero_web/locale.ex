defmodule KlassHeroWeb.Locale do
  @moduledoc """
  Everything the web layer needs to know about locales.

  The *set* is not declared here — `KlassHero.Shared.Locales` owns it, sourced
  from one binding in `config/config.exs` that also feeds the Gettext key
  `mix lint_translations` reads (#1227). Before that, this module and
  `KlassHero.Accounts.User.locale_changeset/2` each kept their own copy, and they
  disagreed in a way nothing surfaced: adding a locale here alone left the
  changeset rejecting what this module accepted, so choosing it failed with
  "Failed to update language preference." and no explanation anywhere.

  What lives here is the web's own answers about locales:

  - `validate/1` coerces rather than fails. Every caller receives a locale from
    untrusted input — a `?locale=` param, a session cookie written by an older
    release, a `users.locale` column holding a value since retired — and the
    right response to all of them is to render the default, not to raise. The
    changeset is the strict half of that pair and rejects instead.
  - `label/1` and `flag/1` are display metadata, which has no business in the
    domain. Labels are endonyms — a language's own name for itself — so they are
    deliberately not run through Gettext: an English speaker sees "Deutsch" too.
  - `url_for/2` builds the canonical and hreflang URLs.
  """

  alias KlassHero.Shared.Locales

  @doc "Every locale the app can render."
  defdelegate supported(), to: Locales

  @doc "The locale used when nothing better is known."
  defdelegate default(), to: Locales

  @doc "Whether the given term is a locale the app can render."
  defdelegate supported?(locale), to: Locales

  @doc "Coerces any term to a supported locale, falling back to `default/0`."
  def validate(locale) do
    if Locales.supported?(locale), do: locale, else: Locales.default()
  end

  @doc """
  The locale's own name for itself, or `nil` if it has none.

  Returning `nil` rather than raising keeps a half-configured locale off the
  settings page instead of crashing it. The "every supported locale is fully
  wired" test in `locale_test.exs` is what makes the omission loud.
  """
  def label("en"), do: "English"
  def label("de"), do: "Deutsch"
  def label(_locale), do: nil

  @doc "The locale's flag, or `nil` if it has none. See `label/1`."
  def flag("en"), do: "🇬🇧"
  def flag("de"), do: "🇩🇪"
  def flag(_locale), do: nil

  @doc """
  The absolute URL serving `path` in `locale`, for `rel=canonical` and
  `rel=alternate hreflang`.

  Passing `nil` yields the bare path — the `x-default` target, which serves
  whatever the visitor's session or `Accept-Language` header implies. Every
  other locale gets an explicit `?locale=`, so canonical never names the bare
  path: that would leave it and `?locale=en` as two self-canonical URLs with
  identical content.
  """
  def url_for(path, nil), do: base_url() <> path
  def url_for(path, locale), do: base_url() <> path <> "?locale=" <> validate(locale)

  defp base_url, do: Application.get_env(:klass_hero, :app_base_url, "http://localhost:4000")
end
