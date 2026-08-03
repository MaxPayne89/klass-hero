defmodule KlassHeroWeb.LocaleTest do
  @moduledoc """
  The web layer's answers about locales.

  The *set* is asserted in `KlassHero.Shared.LocalesTest`, which is where it now
  lives; this file only checks that the web layer reads it rather than keeping a
  copy (#1227), plus the concerns that are genuinely the web's own.

  `validate/1` never fails — an unknown locale renders the default rather than
  raising, because every caller receives it from untrusted input (`?locale=`, a
  session written by an older release, a `:locale` column predating a value
  being retired).
  """
  use ExUnit.Case, async: true

  alias KlassHero.Accounts.User
  alias KlassHero.Shared.Locales
  alias KlassHeroWeb.I18nHelpers
  alias KlassHeroWeb.Locale

  describe "supported/0 and default/0" do
    test "read the domain's set rather than keeping a copy" do
      assert Locale.supported() == Locales.supported()
      assert Locale.default() == Locales.default()
    end
  end

  describe "the supported set is fully wired" do
    # The one assertion that makes adding a locale safe. Each half fails in a
    # different, silent way on its own: no PO directory means untranslated
    # passthrough, no label or flag means a blank radio on the settings page.
    test "every supported locale has translations, a label and a flag" do
      for locale <- Locale.supported() do
        assert File.dir?("priv/gettext/#{locale}/LC_MESSAGES"),
               "#{locale} is supported but has no priv/gettext/#{locale}/LC_MESSAGES"

        assert Locale.label(locale), "#{locale} is supported but has no label/1 clause"
        assert Locale.flag(locale), "#{locale} is supported but has no flag/1 clause"
      end
    end

    # The schema and migration column defaults are literals — neither can read
    # config — so the agreement is pinned rather than derived.
    test "the user schema default is the configured default locale" do
      assert %User{}.locale == Locale.default()
    end

    test "an unconfigured locale has no display metadata" do
      refute Locale.label(I18nHelpers.unsupported_locale())
      refute Locale.flag(I18nHelpers.unsupported_locale())
    end
  end

  describe "validate/1" do
    test "passes a supported locale through unchanged" do
      for locale <- Locale.supported() do
        assert Locale.validate(locale) == locale
      end
    end

    # Every entry is either a non-string or a case/region variant of a supported
    # locale, so none can ever become supported — naming a real language like
    # "fr" would make this wrong the day it is added.
    test "coerces anything else to the default, whatever its type" do
      coerced = [I18nHelpers.unsupported_locale(), "", "EN", "de-DE", nil, :de, 123]

      for input <- coerced do
        assert Locale.validate(input) == Locale.default(),
               "expected #{inspect(input)} to coerce to #{inspect(Locale.default())}"
      end
    end
  end

  describe "supported?/1" do
    test "distinguishes a known locale from an unknown one" do
      for locale <- Locale.supported(), do: assert(Locale.supported?(locale))

      refute Locale.supported?(I18nHelpers.unsupported_locale())
      refute Locale.supported?(nil)
    end
  end
end
