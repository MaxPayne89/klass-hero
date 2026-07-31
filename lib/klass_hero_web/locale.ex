defmodule KlassHeroWeb.Locale do
  @moduledoc """
  The supported-locale whitelist, in one place.

  This unifies the web layer's copies — the `SetLocale` plug, the `RestoreLocale`
  hook, and (implicitly) the hardcoded `lang="en"` in the root layout, which had
  drifted far enough to claim English on every German page (#1161).

  `KlassHero.Accounts.User.locale_changeset/2` deliberately keeps its own list:
  the domain cannot depend on a web module. The two agree today, so adding a
  locale here without adding it there would leave the changeset rejecting what
  this module accepts.

  `validate/1` coerces rather than fails. Every caller receives a locale from
  untrusted input — a `?locale=` param, a session cookie written by an older
  release, a `users.locale` column holding a value since retired — and the right
  response to all of them is to render the default, not to raise.
  """

  @supported ~w(en de)
  @default "en"

  @doc "Every locale the app can render."
  def supported, do: @supported

  @doc "The locale used when nothing better is known."
  def default, do: @default

  @doc "Coerces any term to a supported locale, falling back to `default/0`."
  def validate(locale) when locale in @supported, do: locale
  def validate(_locale), do: @default

  @doc "Whether the given term is a locale the app can render."
  def supported?(locale), do: locale in @supported

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
