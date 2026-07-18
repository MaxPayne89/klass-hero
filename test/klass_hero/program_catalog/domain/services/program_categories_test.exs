defmodule KlassHero.ProgramCatalog.Domain.Services.ProgramCategoriesTest do
  @moduledoc """
  Tests for the ProgramCategories domain service.

  All tests are pure unit tests with no database dependencies.
  """

  use ExUnit.Case, async: true

  alias KlassHero.ProgramCatalog.Domain.Services.ProgramCategories

  @all_categories ["sports", "arts", "music", "education", "life-skills", "camps", "workshops"]

  describe "valid_categories/0" do
    test "includes all program categories" do
      valid = ProgramCategories.valid_categories()
      assert Enum.all?(@all_categories, &(&1 in valid))
    end

    test "includes 'all' as a filter-only value" do
      assert "all" in ProgramCategories.valid_categories()
    end

    test "returns a list of strings" do
      assert Enum.all?(ProgramCategories.valid_categories(), &is_binary/1)
    end
  end

  # Every program category validates unchanged, is valid, and is a valid
  # program category (unlike the filter-only "all" value, see below).
  for category <- @all_categories do
    describe "category: #{category}" do
      @category category

      test "validates unchanged, is valid, and is a valid program category" do
        assert ProgramCategories.validate_filter(@category) == @category
        assert ProgramCategories.valid?(@category)
        assert ProgramCategories.valid_program_category?(@category)
      end
    end
  end

  describe "'all' filter-only value" do
    test "validates unchanged and is valid, but is not a valid program category" do
      assert ProgramCategories.validate_filter("all") == "all"
      assert ProgramCategories.valid?("all")
      refute ProgramCategories.valid_program_category?("all")
    end
  end

  describe "validate_filter/1 - defaults to 'all'" do
    test "for nil and unknown category strings" do
      for value <- [nil, "invalid", "dance", ""] do
        assert ProgramCategories.validate_filter(value) == "all", inspect(value)
      end
    end
  end

  describe "valid?/1 and valid_program_category?/1 - unknown categories" do
    test "return false for unrecognized category strings" do
      for value <- ["dance", "coding", ""] do
        refute ProgramCategories.valid?(value), inspect(value)
      end

      for value <- ["dance", ""] do
        refute ProgramCategories.valid_program_category?(value), inspect(value)
      end
    end
  end

  describe "default_category/0" do
    test "returns 'all'" do
      assert ProgramCategories.default_category() == "all"
    end
  end

  describe "program_categories/0" do
    test "returns all categories except 'all'" do
      assert ProgramCategories.program_categories() == @all_categories
    end
  end

  describe "category list consistency" do
    test "valid_categories contains all program_categories plus 'all'" do
      program_cats = ProgramCategories.program_categories()
      valid_cats = ProgramCategories.valid_categories()

      assert length(valid_cats) == length(program_cats) + 1
      assert "all" in valid_cats
      assert Enum.all?(program_cats, &(&1 in valid_cats))
    end
  end
end
