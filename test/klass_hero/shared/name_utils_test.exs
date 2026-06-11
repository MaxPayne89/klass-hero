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

  describe "split_first_last/1" do
    @split_cases [
      {"Max Pergl", {"Max", "Pergl"}, "two-word name"},
      {"Anna Maria Schmidt", {"Anna", "Maria Schmidt"}, "multi-word: rest is last name"},
      {"Cher", {"Cher", ""}, "single name leaves last empty"},
      {"Anna  Maria", {"Anna", "Maria"}, "consecutive spaces collapse, no leading-space leak"},
      {"  Max Pergl  ", {"Max", "Pergl"}, "surrounding whitespace trimmed"},
      {"Max\tPergl", {"Max", "Pergl"}, "tab separator"},
      {"", {"", ""}, "empty string"},
      {"   ", {"", ""}, "whitespace-only"},
      {nil, {"", ""}, "nil"},
      {42, {"", ""}, "non-binary"}
    ]

    test "splits on the first whitespace run, robust to odd spacing" do
      for {input, expected, label} <- @split_cases do
        actual = NameUtils.split_first_last(input)

        assert actual == expected,
               "#{label}: split_first_last(#{inspect(input)}) returned #{inspect(actual)}"
      end
    end
  end
end
