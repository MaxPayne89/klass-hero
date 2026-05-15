defmodule KlassHero.Shared.NameUtilsTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias KlassHero.Shared.NameUtils

  @cases [
    {nil, "?", "nil"},
    {"", "?", "empty string"},
    {"   ", "?", "whitespace-only"},
    {123, "?", "non-binary"},
    {"Emma", "E", "single name"},
    {"emma", "E", "lowercase single name"},
    {"John Doe", "JD", "two-word name"},
    {"john doe smith", "JD", "three-word name (take first two)"},
    {"  Emma  ", "E", "leading and trailing whitespace"},
    {" Emma Watson", "EW", "leading whitespace, two words"},
    {"Anna    Maria", "AM", "consecutive internal whitespace"},
    {"Anna\tMaria", "AM", "tab separator"},
    {"O'Brien Smith", "OS", "punctuation in name"},
    {"Élise Müller", "ÉM", "diacritics preserved and uppercased"}
  ]

  describe "initials_from_name/1" do
    test "canonical cases" do
      for {input, expected, label} <- @cases do
        actual = NameUtils.initials_from_name(input)

        assert actual == expected,
               "#{label}: initials_from_name(#{inspect(input)}) returned #{inspect(actual)}, expected #{inspect(expected)}"
      end
    end

    property "returns uppercase initials of first two tokens for any non-empty token list" do
      check all(
              tokens <-
                list_of(string(:alphanumeric, min_length: 1, max_length: 5),
                  min_length: 1,
                  max_length: 6
                )
            ) do
        name = Enum.join(tokens, " ")
        result = NameUtils.initials_from_name(name)

        expected =
          tokens
          |> Enum.take(2)
          |> Enum.map_join("", &(&1 |> String.first() |> String.upcase()))

        assert result == expected
        assert String.length(result) in 1..2
        assert result == String.upcase(result)
      end
    end
  end
end
