defmodule KlassHero.ProgramCatalog.Adapters.Driven.Persistence.Queries.ProgramQueriesTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.ProgramCatalog.Adapters.Driven.Persistence.Queries.ProgramQueries
  alias KlassHero.ProgramCatalog.Adapters.Driven.Persistence.Schemas.ProgramSchema

  describe "base_query/0" do
    test "returns base query for Program schema" do
      query = ProgramQueries.base_query()

      assert %Ecto.Query{} = query
      assert query.from.source == {"programs", ProgramSchema}
    end
  end

  describe "order_by_creation/2" do
    test "orders by inserted_at DESC and id DESC when direction is :desc" do
      query =
        ProgramQueries.base_query()
        |> ProgramQueries.order_by_creation(:desc)

      assert [
               desc: {{:., [], [{:&, [], [0]}, :inserted_at]}, [], []},
               desc: {{:., [], [{:&, [], [0]}, :id]}, [], []}
             ] = query.order_bys |> hd() |> Map.get(:expr)
    end

    test "orders by inserted_at ASC and id ASC when direction is :asc" do
      query =
        ProgramQueries.base_query()
        |> ProgramQueries.order_by_creation(:asc)

      assert [
               asc: {{:., [], [{:&, [], [0]}, :inserted_at]}, [], []},
               asc: {{:., [], [{:&, [], [0]}, :id]}, [], []}
             ] = query.order_bys |> hd() |> Map.get(:expr)
    end

    test "defaults to :desc when no direction provided" do
      query =
        ProgramQueries.base_query()
        |> ProgramQueries.order_by_creation()

      assert [desc: _, desc: _] = query.order_bys |> hd() |> Map.get(:expr)
    end
  end

  describe "paginate_after_cursor/3" do
    setup do
      cursor_ts = ~U[2024-01-15 12:00:00Z]
      cursor_id = Ecto.UUID.generate()

      %{cursor_ts: cursor_ts, cursor_id: cursor_id}
    end

    test "adds WHERE clause for DESC pagination", %{cursor_ts: cursor_ts, cursor_id: cursor_id} do
      query =
        ProgramQueries.base_query()
        |> ProgramQueries.paginate_after_cursor({cursor_ts, cursor_id}, :desc)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end

    test "adds WHERE clause for ASC pagination", %{cursor_ts: cursor_ts, cursor_id: cursor_id} do
      query =
        ProgramQueries.base_query()
        |> ProgramQueries.paginate_after_cursor({cursor_ts, cursor_id}, :asc)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end

    test "defaults to :desc when no direction provided", %{
      cursor_ts: cursor_ts,
      cursor_id: cursor_id
    } do
      query =
        ProgramQueries.base_query()
        |> ProgramQueries.paginate_after_cursor({cursor_ts, cursor_id})

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "limit_results/2" do
    test "adds LIMIT clause with specified limit" do
      query =
        ProgramQueries.base_query()
        |> ProgramQueries.limit_results(10)

      assert %Ecto.Query{} = query
      assert query.limit != nil
    end

    test "works with different limit values" do
      query =
        ProgramQueries.base_query()
        |> ProgramQueries.limit_results(1)

      assert query.limit != nil

      query =
        ProgramQueries.base_query()
        |> ProgramQueries.limit_results(100)

      assert query.limit != nil
    end
  end

  describe "filter_by_category/2" do
    test "returns query unchanged when category is nil" do
      base = ProgramQueries.base_query()
      query = ProgramQueries.filter_by_category(base, nil)

      assert query == base
    end

    test "returns query unchanged when category is \"all\"" do
      base = ProgramQueries.base_query()
      query = ProgramQueries.filter_by_category(base, "all")

      assert query == base
    end

    test "adds WHERE clause for a specific category" do
      query =
        ProgramQueries.base_query()
        |> ProgramQueries.filter_by_category("sports")

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end

    test "adds WHERE clause for any non-nil, non-all category value" do
      for category <- ["music", "arts", "stem", "dance"] do
        query =
          ProgramQueries.base_query()
          |> ProgramQueries.filter_by_category(category)

        assert length(query.wheres) == 1, "expected 1 WHERE clause for category #{category}"
      end
    end

    test "composes with cursor pagination" do
      cursor_ts = ~U[2024-01-15 12:00:00Z]
      cursor_id = Ecto.UUID.generate()

      query =
        ProgramQueries.base_query()
        |> ProgramQueries.filter_by_category("sports")
        |> ProgramQueries.paginate_after_cursor({cursor_ts, cursor_id}, :desc)

      assert length(query.wheres) == 2
    end
  end

  describe "query composition" do
    test "can compose all query functions together" do
      cursor_ts = ~U[2024-01-15 12:00:00Z]
      cursor_id = Ecto.UUID.generate()

      query =
        ProgramQueries.base_query()
        |> ProgramQueries.paginate_after_cursor({cursor_ts, cursor_id}, :desc)
        |> ProgramQueries.order_by_creation(:desc)
        |> ProgramQueries.limit_results(20)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
      assert length(query.order_bys) == 1
      assert query.limit != nil
    end

    test "order of composition does not affect query structure" do
      cursor_ts = ~U[2024-01-15 12:00:00Z]
      cursor_id = Ecto.UUID.generate()

      # Different composition order
      query1 =
        ProgramQueries.base_query()
        |> ProgramQueries.order_by_creation(:desc)
        |> ProgramQueries.paginate_after_cursor({cursor_ts, cursor_id}, :desc)
        |> ProgramQueries.limit_results(20)

      query2 =
        ProgramQueries.base_query()
        |> ProgramQueries.limit_results(20)
        |> ProgramQueries.order_by_creation(:desc)
        |> ProgramQueries.paginate_after_cursor({cursor_ts, cursor_id}, :desc)

      # Both should have same number of clauses
      assert length(query1.wheres) == length(query2.wheres)
      assert length(query1.order_bys) == length(query2.order_bys)
      assert query1.limit != nil
      assert query2.limit != nil
    end
  end
end
