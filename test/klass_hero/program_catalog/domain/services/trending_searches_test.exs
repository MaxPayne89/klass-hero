defmodule KlassHero.ProgramCatalog.Domain.Services.TrendingSearchesTest do
  use ExUnit.Case, async: true

  alias KlassHero.ProgramCatalog.Domain.Services.TrendingSearches

  doctest TrendingSearches

  describe "list/0" do
    test "returns all trending search terms" do
      result = TrendingSearches.list()

      assert is_list(result)
      assert length(result) == 5
      assert "Swimming" in result
      assert "Math Tutor" in result
      assert "Summer Camp" in result
      assert "Piano" in result
      assert "Soccer" in result
    end

    test "returns strings" do
      result = TrendingSearches.list()

      assert Enum.all?(result, &is_binary/1)
    end
  end

  describe "list/1" do
    test "limits results to max count" do
      result = TrendingSearches.list(3)

      assert length(result) == 3
      assert result == ["Swimming", "Math Tutor", "Summer Camp"]
    end

    test "returns all when max exceeds available" do
      result = TrendingSearches.list(10)

      assert length(result) == 5
    end

    test "returns single item when max is 1" do
      result = TrendingSearches.list(1)

      assert result == ["Swimming"]
    end
  end
end
