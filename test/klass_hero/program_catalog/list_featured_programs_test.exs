defmodule KlassHero.ProgramCatalog.ListFeaturedProgramsTest do
  # async: false — the row-count assertion uses a process-global telemetry
  # handler; concurrent tests' queries would otherwise inflate the count.
  use KlassHero.DataCase, async: false

  import KlassHero.Factory

  alias KlassHero.ProgramCatalog
  alias KlassHero.QueryCounter

  describe "list_featured_programs/0" do
    test "returns at most 2 active listings" do
      insert_list(4, :program_listing_schema)

      assert length(ProgramCatalog.list_featured_programs()) == 2
    end

    test "fetches at most 2 rows from the database (bounded in SQL, not trimmed in Elixir)" do
      insert_list(4, :program_listing_schema)

      {result, rows_fetched} =
        QueryCounter.count_rows(fn -> ProgramCatalog.list_featured_programs() end)

      assert length(result) == 2
      # The whole point of the fix: don't pull every active listing back just to keep 2.
      assert rows_fetched <= 2
    end

    test "orders by title ascending" do
      insert(:program_listing_schema, title: "Zebra")
      insert(:program_listing_schema, title: "Apple")
      insert(:program_listing_schema, title: "Mango")

      assert [%{title: "Apple"}, %{title: "Mango"}] = ProgramCatalog.list_featured_programs()
    end

    test "excludes expired listings (end_date in the past)" do
      insert(:program_listing_schema, title: "Active", end_date: nil)
      insert(:program_listing_schema, title: "Expired", end_date: Date.add(Date.utc_today(), -1))

      titles = ProgramCatalog.list_featured_programs() |> Enum.map(& &1.title)

      assert "Active" in titles
      refute "Expired" in titles
    end
  end
end
