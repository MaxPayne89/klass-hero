defmodule KlassHero.Shared.LocalesTest do
  @moduledoc """
  The supported-locale set, declared once.

  Before #1227 the same list was written out six times — here, in
  `User.locale_changeset/2`, in the Gettext config, in the root layout's
  hreflang tags, in the settings radios, and in a test helper. The two that
  disagreed silently were the changeset (which rejects) and the web layer (which
  coerces): adding a locale to one alone left users unable to select it, with
  nothing in the web layer explaining the failure.
  """
  use ExUnit.Case, async: true

  alias KlassHero.Shared.Locales

  doctest Locales

  describe "supported/0 and default/0" do
    test "the default is itself a supported locale" do
      assert Locales.default() in Locales.supported()
    end

    test "supports exactly English and German" do
      assert Enum.sort(Locales.supported()) == ["de", "en"]
    end

    # The whole point of #1227: one binding in config/config.exs feeds both this
    # module and the Gettext key that `mix lint_translations` reads. If these
    # ever disagree, the binding was bypassed and a locale can be added that has
    # no enforced translations.
    test "agrees with the Gettext config the translation linter reads" do
      gettext_config = Application.fetch_env!(:klass_hero, KlassHeroWeb.Gettext)

      assert Enum.sort(Keyword.fetch!(gettext_config, :locales)) ==
               Enum.sort(Locales.supported())

      assert Keyword.fetch!(gettext_config, :default_locale) == Locales.default()
    end
  end

  describe "supported?/1" do
    # Every false case is a non-string or a case/region variant of a supported
    # locale — none can ever itself become supported, so adding a language
    # cannot silently invert what these assert. Naming a plain code like "fr"
    # would. (The plain-code path is covered in KlassHeroWeb.LocaleTest, which
    # is where the helper deriving one lives.)
    @cases [
      {"en", true},
      {"de", true},
      {"", false},
      {"EN", false},
      {"de-DE", false},
      {nil, false},
      {:de, false},
      {123, false}
    ]

    test "separates a supported locale from anything else, whatever its type" do
      for {input, expected} <- @cases do
        assert Locales.supported?(input) == expected,
               "expected supported?(#{inspect(input)}) to be #{expected}"
      end
    end
  end
end
