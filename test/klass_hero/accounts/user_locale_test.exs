defmodule KlassHero.Accounts.UserLocaleTest do
  @moduledoc """
  The changeset that decides whether a language choice can be stored.

  It is the strict half of an asymmetric pair: `KlassHeroWeb.Locale.validate/1`
  coerces an unsupported locale to the default, while this rejects it. That is
  correct — untrusted input should render the default rather than raise, but it
  should never be written to a user's profile. It only holds while both halves
  read the same set, which is why these assertions derive from
  `Shared.Locales.supported/0` rather than naming "en" and "de" again (#1227).
  """
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias KlassHero.Accounts.User
  alias KlassHero.Shared.Locales

  describe "locale_changeset/2" do
    test "accepts every locale the app claims to support" do
      for locale <- Locales.supported() do
        changeset = User.locale_changeset(%User{}, %{locale: locale})

        assert changeset.valid?,
               "#{locale} is in Locales.supported/0 but the changeset rejects it: " <>
                 inspect(changeset.errors)

        # get_field, not get_change: casting the locale a user already has is a
        # no-op change, so get_change would be nil for whichever locale is the
        # schema default.
        assert Changeset.get_field(changeset, :locale) == locale
      end
    end

    # Deliberately not a plausible language code like "fr": adding French would
    # make this fixture wrong. Case and region variants of locales the app does
    # support can never themselves be supported — every configured code is a
    # bare lowercase two-letter string.
    @never_locales ["EN", "de-DE", "en-US", "not-a-locale"]

    test "rejects anything outside that set" do
      assert Enum.all?(@never_locales, &(&1 not in Locales.supported())),
             "fixture overlaps Locales.supported/0 — this test would be vacuous"

      for locale <- @never_locales do
        changeset = User.locale_changeset(%User{locale: "en"}, %{locale: locale})

        refute changeset.valid?, "#{inspect(locale)} was accepted as a locale"
        assert Keyword.has_key?(changeset.errors, :locale)
      end
    end

    test "requires a locale rather than silently keeping the old one" do
      changeset = User.locale_changeset(%User{locale: "en"}, %{locale: nil})

      refute changeset.valid?
      assert {"can't be blank", _meta} = changeset.errors[:locale]
    end

    # Not the same as nil, and not a no-op either: Ecto's :empty_values replaces
    # an empty param with the *field default*, so this resets a German user to
    # English rather than erroring. Harmless in practice — the only write path
    # runs it through `KlassHeroWeb.Locale.validate/1` first, which maps "" to
    # the default anyway — but pinned so the behaviour is deliberate.
    test "an empty string resets to the default locale rather than erroring" do
      changeset = User.locale_changeset(%User{locale: "de"}, %{locale: ""})

      assert changeset.valid?
      assert Changeset.get_field(changeset, :locale) == Locales.default()
    end

    # The schema and migration defaults are literals — neither can read config —
    # so they are pinned here instead.
    test "the schema default is the configured default locale" do
      assert %User{}.locale == Locales.default()
    end
  end
end
