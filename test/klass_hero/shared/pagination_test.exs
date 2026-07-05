defmodule KlassHero.Shared.PaginationTest do
  use ExUnit.Case, async: true

  alias KlassHero.Shared.Pagination.{PageParams, PageResult}

  describe "PageParams.new/1" do
    test "creates PageParams with default limit when no attrs provided" do
      assert {:ok, params} = PageParams.new()
      assert params.limit == 20
      assert is_nil(params.cursor)
    end

    test "creates PageParams with custom limit" do
      assert {:ok, params} = PageParams.new(limit: 50)
      assert params.limit == 50
      assert is_nil(params.cursor)
    end

    test "creates PageParams with cursor" do
      cursor = "base64_cursor"
      assert {:ok, params} = PageParams.new(cursor: cursor)
      assert params.limit == 20
      assert params.cursor == cursor
    end

    test "creates PageParams with both limit and cursor" do
      cursor = "base64_cursor"
      assert {:ok, params} = PageParams.new(limit: 10, cursor: cursor)
      assert params.limit == 10
      assert params.cursor == cursor
    end
  end

  describe "PageParams.validate/1" do
    test "accepts valid limit within range 1-100" do
      assert {:ok, params} = PageParams.new(limit: 1)
      assert params.limit == 1

      assert {:ok, params} = PageParams.new(limit: 50)
      assert params.limit == 50

      assert {:ok, params} = PageParams.new(limit: 100)
      assert params.limit == 100
    end

    test "constrains limit below minimum to 1" do
      assert {:ok, params} = PageParams.new(limit: 0)
      assert params.limit == 1

      assert {:ok, params} = PageParams.new(limit: -5)
      assert params.limit == 1
    end

    test "constrains limit above maximum to 100" do
      assert {:ok, params} = PageParams.new(limit: 101)
      assert params.limit == 100

      assert {:ok, params} = PageParams.new(limit: 500)
      assert params.limit == 100
    end

    test "returns error for non-integer limit" do
      params = %PageParams{limit: "not_an_integer", cursor: nil}
      assert {:error, :invalid_limit} = PageParams.validate(params)

      params = %PageParams{limit: 12.5, cursor: nil}
      assert {:error, :invalid_limit} = PageParams.validate(params)

      params = %PageParams{limit: nil, cursor: nil}
      assert {:error, :invalid_limit} = PageParams.validate(params)
    end
  end

  describe "PageResult.new/3" do
    test "creates PageResult with items, next_cursor, and has_more" do
      items = ["item1", "item2", "item3"]
      next_cursor = "next_cursor_value"
      has_more = true

      result = PageResult.new(items, next_cursor, has_more)

      assert result.items == items
      assert result.next_cursor == next_cursor
      assert result.has_more == has_more
      assert result.metadata.returned_count == 3
    end

    test "creates PageResult with empty items list" do
      result = PageResult.new([], nil, false)

      assert result.items == []
      assert is_nil(result.next_cursor)
      assert result.has_more == false
      assert result.metadata.returned_count == 0
    end

    test "creates PageResult with nil next_cursor when no more pages" do
      items = ["item1", "item2"]
      result = PageResult.new(items, nil, false)

      assert result.items == items
      assert is_nil(result.next_cursor)
      assert result.has_more == false
      assert result.metadata.returned_count == 2
    end

    test "includes returned_count in metadata" do
      items = Enum.to_list(1..25)
      result = PageResult.new(items, "cursor", true)

      assert result.metadata.returned_count == 25
    end
  end
end
