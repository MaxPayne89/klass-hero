defmodule KlassHero.ProgramCatalog.Domain.Services.ProgramFilterTest do
  @moduledoc """
  Tests for the ProgramFilter domain service.

  This test suite verifies program filtering with word-boundary matching
  and special character normalization. The service is a pure function with no side effects.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  import KlassHero.Factory

  alias KlassHero.ProgramCatalog.Domain.Services.ProgramFilter

  defp programs_with_titles(titles), do: Enum.map(titles, &build(:program, title: &1))
  defp result_titles(programs), do: Enum.map(programs, & &1.title)

  @sample_titles [
    "After School Soccer",
    "Summer Dance Camp",
    "Kids Yoga Flow",
    "Basketball Training",
    "Art! & Crafts"
  ]

  # Every row exercises the same contract: filter titles by word-boundary
  # prefix match, case-insensitive, punctuation-stripped, accents preserved.
  @match_cases [
    {@sample_titles, "after", ["After School Soccer"], "prefix match at start of title"},
    {@sample_titles, "school", ["After School Soccer"], "prefix match mid-title word"},
    {@sample_titles, "so", ["After School Soccer"], "short prefix match"},
    {@sample_titles, "soccer", ["After School Soccer"], "full-word match"},
    {@sample_titles, "nonexistent", [], "no matches"},
    {[], "soccer", [], "empty programs list"},
    {["Summer Soccer", "Summer Dance", "Winter Soccer"], "summer", ["Summer Soccer", "Summer Dance"],
     "multiple matches preserve input order"},
    {["Kids Yoga Flow", "Adult Yoga Class", "Meditation Flow"], "yoga", ["Kids Yoga Flow", "Adult Yoga Class"],
     "progressive refinement: 'yoga'"},
    {["Kids Yoga Flow", "Adult Yoga Class", "Meditation Flow"], "flow", ["Kids Yoga Flow", "Meditation Flow"],
     "progressive refinement: 'flow'"},
    {["Soccer Stars", "Social Club", "Art Adventure"], "soccer", ["Soccer Stars"], "narrowing: full word 'soccer'"},
    {["Soccer Stars", "Social Club", "Art Adventure"], "soc", ["Soccer Stars", "Social Club"],
     "narrowing: shared prefix 'soc'"},
    {["Soccer Stars", "Social Club", "Art Adventure"], "so", ["Soccer Stars", "Social Club"],
     "narrowing: shorter prefix 'so'"},
    {["Soccer", "Dance"], "soc", ["Soccer"], "single-word titles"},
    {["Advanced Soccer Training Camp for Young Athletes and Future Champions"], "future",
     ["Advanced Soccer Training Camp for Young Athletes and Future Champions"], "very long title"},
    {["Kids Soccer Camp", "Adult Soccer League", "Kids Dance Class"], "kids s", [],
     "multi-word query has no AND logic"},
    {["Basketball Training"], "ball", [], "rejects substring match (word-boundary)"},
    {["Art! & Crafts", "Kids' Yoga"], "art", ["Art! & Crafts"], "punctuation stripped from title: 'art'"},
    {["Art! & Crafts", "Kids' Yoga"], "kids", ["Kids' Yoga"], "punctuation stripped from title: 'kids'"},
    {["Art & Crafts"], "art!", ["Art & Crafts"], "punctuation stripped from query"},
    {["Art! & Crafts", "Dance Class"], "art!", ["Art! & Crafts"], "punctuation stripped from both title and query"},
    {["Summer   Dance    Camp"], "dance", ["Summer   Dance    Camp"], "consecutive spaces collapse for matching"},
    {["École de Danse", "Niños Yoga", "Café Cultural"], "école", ["École de Danse"], "accented: école"},
    {["École de Danse", "Niños Yoga", "Café Cultural"], "niños", ["Niños Yoga"], "accented: niños"},
    {["École de Danse", "Niños Yoga", "Café Cultural"], "café", ["Café Cultural"], "accented: café"},
    {["Fußball für Kinder", "Äpfel und Birnen"], "fußball", ["Fußball für Kinder"], "German: ß preserved"},
    {["Fußball für Kinder", "Äpfel und Birnen"], "äpfel", ["Äpfel und Birnen"], "German: ä preserved"},
    {["São Paulo Soccer", "Ação Cultural"], "são", ["São Paulo Soccer"], "Portuguese: ã preserved"},
    {["São Paulo Soccer", "Ação Cultural"], "ação", ["Ação Cultural"], "Portuguese: ç preserved"},
    {["Москва Basketball", "Київ Dance"], "москва", ["Москва Basketball"], "Cyrillic script"},
    {["Москва Basketball", "Київ Dance"], "київ", ["Київ Dance"], "Cyrillic script"},
    {["Αθήνα Yoga", "Ελληνικά Lessons"], "αθήνα", ["Αθήνα Yoga"], "Greek script"},
    {["Αθήνα Yoga", "Ελληνικά Lessons"], "ελληνικά", ["Ελληνικά Lessons"], "Greek script"},
    {["Café São Москва École"], "café", ["Café São Москва École"], "mixed-script title: café fragment"},
    {["Café São Москва École"], "são", ["Café São Москва École"], "mixed-script title: são fragment"},
    {["Café São Москва École"], "москва", ["Café São Москва École"], "mixed-script title: москва fragment"},
    {["Café São Москва École"], "école", ["Café São Москва École"], "mixed-script title: école fragment"},
    {["Café! & École"], "café", ["Café! & École"], "accented characters with special-character normalization"}
  ]

  describe "execute/2 - word-boundary title matching" do
    test "matches by prefix across basic, edge-case, and international titles" do
      for {titles, query, expected, label} <- @match_cases do
        result = titles |> programs_with_titles() |> ProgramFilter.execute(query)

        assert result_titles(result) == expected,
               "#{label}: execute(#{inspect(titles)}, #{inspect(query)}) returned " <>
                 "#{inspect(result_titles(result))}, expected #{inspect(expected)}"
      end
    end
  end

  describe "execute/2 - empty and whitespace queries" do
    test "returns the input list unchanged" do
      programs = sample_programs()

      for query <- ["", "   ", "\t\t", " \t \n "] do
        assert ProgramFilter.execute(programs, query) == programs,
               "query #{inspect(query)} should pass programs through unchanged"
      end
    end
  end

  describe "execute/2 - properties" do
    property "matching is case-insensitive for any query" do
      check all(query <- string(:alphanumeric, max_length: 12)) do
        programs = sample_programs()

        assert ProgramFilter.execute(programs, query) ==
                 ProgramFilter.execute(programs, String.upcase(query))
      end
    end

    test "case-insensitivity known corners: ASCII and accented queries" do
      programs = [
        build(:program, title: "After School Soccer"),
        build(:program, title: "École de Français")
      ]

      assert ProgramFilter.execute(programs, "soccer") == ProgramFilter.execute(programs, "SOCCER")
      assert ProgramFilter.execute(programs, "école") == ProgramFilter.execute(programs, "ÉCOLE")
      assert ProgramFilter.execute(programs, "école") == ProgramFilter.execute(programs, "ÉcOlE")
    end

    property "a query that isn't a prefix of any word never matches (word-boundary enforcement)" do
      check all(
              fragment <- string(:alphanumeric, min_length: 1, max_length: 8),
              padding <- string(:alphanumeric, max_length: 8)
            ) do
        # The service normalizes (downcases) both title and query before
        # comparing, so force the title's first character to differ from the
        # *normalized* fragment's first character. That guarantees fragment
        # can never be a true prefix of the title, regardless of what
        # word-internal position it was generated to sit at.
        safe_first = if String.starts_with?(String.downcase(fragment), "a"), do: "b", else: "a"
        title = safe_first <> padding <> fragment

        programs = [build(:program, title: title)]

        assert ProgramFilter.execute(programs, fragment) == []
      end
    end

    property "filtering an already-filtered result is idempotent" do
      check all(query <- string(:alphanumeric, max_length: 12)) do
        programs = sample_programs()
        once = ProgramFilter.execute(programs, query)

        assert ProgramFilter.execute(once, query) == once
      end
    end
  end

  describe "sanitize_query/1" do
    test "trims whitespace" do
      assert ProgramFilter.sanitize_query("  art  ") == "art"
    end

    test "returns empty string for nil" do
      assert ProgramFilter.sanitize_query(nil) == ""
    end

    test "limits query length to 100 characters" do
      long_query = String.duplicate("a", 150)

      assert String.length(ProgramFilter.sanitize_query(long_query)) == 100
    end

    property "never returns more than 100 characters" do
      check all(query <- string(:alphanumeric, max_length: 500)) do
        assert String.length(ProgramFilter.sanitize_query(query)) <= 100
      end
    end
  end
end
