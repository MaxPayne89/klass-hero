defmodule KlassHero.Shared.Locales do
  @moduledoc """
  The supported-locale set, for every layer.

  Lives in the Shared kernel for the same reason `KlassHero.Shared.Categories`
  does: both a domain changeset (`KlassHero.Accounts.User.locale_changeset/2`)
  and the web layer (`KlassHeroWeb.Locale`) need the same list, and the domain
  cannot depend on a web module to get it.

  The list is sourced from config rather than declared here. `config/config.exs`
  also feeds it to the `KlassHeroWeb.Gettext` key that `mix lint_translations`
  reads, and config is evaluated before this module exists — so config, not this
  module, has to be the one declaration (#1227).

  This module answers *which* locales exist. How an unsupported one is handled
  differs by caller and is not decided here: the changeset rejects it, while
  `KlassHeroWeb.Locale.validate/1` coerces it to `default/0`, because every web
  caller receives a locale from untrusted input.
  """

  @supported Application.compile_env!(:klass_hero, [:locales, :supported])
  @default Application.compile_env!(:klass_hero, [:locales, :default])

  @doc "Every locale the app supports."
  @spec supported() :: [String.t()]
  def supported, do: @supported

  @doc "The locale used when nothing better is known."
  @spec default() :: String.t()
  def default, do: @default

  @doc """
  Whether the given term is a supported locale.

  Accepts any term, not just a string — callers pass values straight from a query
  param, a session written by an older release, or a `users.locale` column
  holding a since-retired value.

  ## Examples

      iex> KlassHero.Shared.Locales.supported?("de")
      true

      iex> KlassHero.Shared.Locales.supported?("de-DE")
      false

      iex> KlassHero.Shared.Locales.supported?(nil)
      false
  """
  @spec supported?(term()) :: boolean()
  def supported?(locale), do: locale in @supported
end
