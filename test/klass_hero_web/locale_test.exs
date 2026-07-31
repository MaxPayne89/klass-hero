defmodule KlassHeroWeb.LocaleTest do
  @moduledoc """
  The locale whitelist, in one place.

  `validate/1` never fails — an unknown locale renders the default rather than
  raising, because every caller receives it from untrusted input (`?locale=`, a
  session written by an older release, a `:locale` column predating a value
  being retired).
  """
  use ExUnit.Case, async: true

  alias KlassHeroWeb.Locale

  describe "supported/0 and default/0" do
    test "the default is itself a supported locale" do
      assert Locale.default() in Locale.supported()
    end

    test "supports exactly English and German" do
      assert Enum.sort(Locale.supported()) == ["de", "en"]
    end
  end

  describe "validate/1" do
    @cases [
      {"en", "en"},
      {"de", "de"},
      {"fr", "en"},
      {"", "en"},
      {"EN", "en"},
      {"de-DE", "en"},
      {nil, "en"},
      {:de, "en"},
      {123, "en"}
    ]

    for {input, expected} <- @cases do
      test "#{inspect(input)} validates to #{inspect(expected)}" do
        assert Locale.validate(unquote(input)) == unquote(expected),
               "expected #{inspect(unquote(input))} to validate to #{inspect(unquote(expected))}"
      end
    end
  end

  describe "supported?/1" do
    test "distinguishes a known locale from an unknown one" do
      assert Locale.supported?("de")
      refute Locale.supported?("fr")
      refute Locale.supported?(nil)
    end
  end
end
