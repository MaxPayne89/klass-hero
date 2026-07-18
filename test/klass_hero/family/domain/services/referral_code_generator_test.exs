defmodule KlassHero.Family.Domain.Services.ReferralCodeGeneratorTest do
  @moduledoc """
  Tests for the ReferralCodeGenerator domain service.

  All tests are pure unit tests with no database dependencies.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias KlassHero.Family.Domain.Services.ReferralCodeGenerator

  # Every row exercises the same contract: generate/2 uppercases the
  # extracted first word, then joins it with location and year_suffix as-is.
  @generate_cases [
    {"Alice", [location: "BERLIN", year_suffix: "26"], "ALICE-BERLIN-26", "basic format"},
    {"alice", [location: "LONDON", year_suffix: "26"], "ALICE-LONDON-26", "uppercases first name"},
    {"John Smith", [location: "NYC", year_suffix: "26"], "JOHN-NYC-26", "extracts first word of a two-part name"},
    {"Mary Jane Watson", [location: "NYC", year_suffix: "26"], "MARY-NYC-26",
     "extracts first word of a three-part name"},
    {"Madonna", [location: "PARIS", year_suffix: "26"], "MADONNA-PARIS-26", "single-word name"},
    {"Hans Mueller", [location: "BERLIN", year_suffix: "25"], "HANS-BERLIN-25", "standard two-part name"},
    {"Test", [location: "BERLIN", year_suffix: "09"], "TEST-BERLIN-09", "zero-prefixed year suffix"},
    {"Test", [location: "BERLIN", year_suffix: "99"], "TEST-BERLIN-99", "two-digit year suffix"},
    {"Emma", [location: "MUNICH", year_suffix: "26"], "EMMA-MUNICH-26", "custom location"},
    {"Emma", [location: "munich", year_suffix: "26"], "EMMA-munich-26", "location casing is caller-controlled"}
  ]

  describe "generate/2" do
    test "known name/opts combinations produce the expected code" do
      for {name, opts, expected, label} <- @generate_cases do
        assert ReferralCodeGenerator.generate(name, opts) == expected, label
      end
    end

    test "defaults location to BERLIN and year_suffix to the current two-digit year" do
      expected_year =
        Date.utc_today().year |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")

      assert ReferralCodeGenerator.generate("Bob") == "BOB-BERLIN-#{expected_year}"
    end
  end

  describe "generate/2 - properties" do
    property "code matches FIRSTNAME-LOCATION-YEAR shape; first segment is the upcased first word" do
      check all(
              first_word <- member_of(~w(Alice Bob Zoe Xavier Yuki Wendy Q Mo Priya)),
              rest_of_name <- one_of([constant(nil), member_of(~w(Jane Lee Park Watson Kim))]),
              location <- member_of(~w(BERLIN LONDON NYC PARIS MUNICH TOKYO)),
              year_int <- integer(0..99)
            ) do
        name = if is_nil(rest_of_name), do: first_word, else: "#{first_word} #{rest_of_name}"
        year_suffix = year_int |> Integer.to_string() |> String.pad_leading(2, "0")

        code = ReferralCodeGenerator.generate(name, location: location, year_suffix: year_suffix)

        assert code =~ ~r/^[A-Z]+-[A-Z]+-\d{2}$/
        assert String.split(code, "-") == [String.upcase(first_word), location, year_suffix]
      end
    end
  end
end
