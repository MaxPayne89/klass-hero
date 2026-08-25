defmodule KlassHero.Participation.Adapters.Driven.Persistence.Queries.ParticipationQueriesTest do
  @moduledoc """
  Tests for ParticipationQueries composable query functions.

  Tests verify the query builder pattern where each function returns
  an Ecto.Query that can be piped into other query functions.
  """

  use KlassHero.DataCase, async: true

  alias KlassHero.Participation.Adapters.Driven.Persistence.Queries.ParticipationQueries
  alias KlassHero.Participation.ParticipationRecord

  describe "base/0" do
    test "returns base query for ParticipationRecord" do
      query = ParticipationQueries.base()

      assert %Ecto.Query{} = query
      assert query.from.source == {"participation_records", ParticipationRecord}
    end
  end

  describe "by_session/2" do
    test "adds WHERE clause for session ID" do
      session_id = Ecto.UUID.generate()

      query =
        ParticipationQueries.base()
        |> ParticipationQueries.by_session(session_id)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "by_child/2" do
    test "adds WHERE clause for child ID" do
      child_id = Ecto.UUID.generate()

      query =
        ParticipationQueries.base()
        |> ParticipationQueries.by_child(child_id)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "by_children/2" do
    test "adds WHERE IN clause for multiple child IDs" do
      child_ids = [Ecto.UUID.generate(), Ecto.UUID.generate()]

      query =
        ParticipationQueries.base()
        |> ParticipationQueries.by_children(child_ids)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end

    test "works with single child ID in list" do
      child_ids = [Ecto.UUID.generate()]

      query =
        ParticipationQueries.base()
        |> ParticipationQueries.by_children(child_ids)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end

    test "works with empty list" do
      child_ids = []

      query =
        ParticipationQueries.base()
        |> ParticipationQueries.by_children(child_ids)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "by_status/2" do
    test "adds WHERE clause for single status atom" do
      query =
        ParticipationQueries.base()
        |> ParticipationQueries.by_status(:checked_in)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end

    test "adds WHERE IN clause for list of statuses" do
      query =
        ParticipationQueries.base()
        |> ParticipationQueries.by_status([:checked_in, :checked_out])

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "by_date_range/3" do
    test "adds JOIN with sessions and WHERE clause for date range" do
      start_date = ~D[2025-01-01]
      end_date = ~D[2025-01-31]

      query =
        ParticipationQueries.base()
        |> ParticipationQueries.by_date_range(start_date, end_date)

      assert %Ecto.Query{} = query
      assert length(query.joins) == 1
      assert length(query.wheres) == 1
    end
  end

  describe "order_by_session_date_desc/1" do
    test "orders by session_date and start_time descending" do
      start_date = ~D[2025-01-01]
      end_date = ~D[2025-01-31]

      query =
        ParticipationQueries.base()
        |> ParticipationQueries.by_date_range(start_date, end_date)
        |> ParticipationQueries.order_by_session_date_desc()

      assert %Ecto.Query{} = query
      assert length(query.order_bys) == 1
    end
  end

  describe "order_by_inserted_desc/1" do
    test "orders by inserted_at descending" do
      query =
        ParticipationQueries.base()
        |> ParticipationQueries.order_by_inserted_desc()

      assert %Ecto.Query{} = query
      assert length(query.order_bys) == 1
    end
  end

  describe "preload_session/1" do
    test "adds preload for session association" do
      query =
        ParticipationQueries.base()
        |> ParticipationQueries.preload_session()

      assert %Ecto.Query{} = query
      assert length(query.preloads) == 1
    end
  end

  describe "limit_results/2" do
    test "adds LIMIT clause with specified limit" do
      query =
        ParticipationQueries.base()
        |> ParticipationQueries.limit_results(10)

      assert %Ecto.Query{} = query
      assert query.limit.params == [{10, :integer}]
    end

    test "works with different limit values" do
      query1 =
        ParticipationQueries.base()
        |> ParticipationQueries.limit_results(1)

      query2 =
        ParticipationQueries.base()
        |> ParticipationQueries.limit_results(100)

      assert query1.limit.params == [{1, :integer}]
      assert query2.limit.params == [{100, :integer}]
    end
  end

  describe "select_summary/1" do
    test "selects only summary fields" do
      query =
        ParticipationQueries.base()
        |> ParticipationQueries.select_summary()

      assert %Ecto.Query{} = query
      # "only summary fields" is the claim, so name them.
      assert {:%{}, _, fields} = query.select.expr

      assert Enum.map(fields, &elem(&1, 0)) == [
               :id,
               :session_id,
               :child_id,
               :status,
               :check_in_at,
               :check_out_at
             ]
    end
  end

  describe "query composition" do
    test "can compose filtering and ordering functions together" do
      session_id = Ecto.UUID.generate()

      query =
        ParticipationQueries.base()
        |> ParticipationQueries.by_session(session_id)
        |> ParticipationQueries.by_status(:checked_in)
        |> ParticipationQueries.order_by_inserted_desc()
        |> ParticipationQueries.limit_results(20)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 2
      assert length(query.order_bys) == 1
      assert query.limit.params == [{20, :integer}]
    end

    test "can compose child filter with date range ordering" do
      child_id = Ecto.UUID.generate()
      start_date = ~D[2025-01-01]
      end_date = ~D[2025-01-31]

      query =
        ParticipationQueries.base()
        |> ParticipationQueries.by_child(child_id)
        |> ParticipationQueries.by_date_range(start_date, end_date)
        |> ParticipationQueries.order_by_session_date_desc()
        |> ParticipationQueries.limit_results(50)

      assert %Ecto.Query{} = query
      # by_child adds 1 where, by_date_range adds 1 where
      assert length(query.wheres) == 2
      assert length(query.joins) == 1
      assert length(query.order_bys) == 1
      assert query.limit.params == [{50, :integer}]
    end

    test "can compose with multiple children filter" do
      child_ids = [Ecto.UUID.generate(), Ecto.UUID.generate()]

      query =
        ParticipationQueries.base()
        |> ParticipationQueries.by_children(child_ids)
        |> ParticipationQueries.by_status([:registered, :checked_in])
        |> ParticipationQueries.order_by_inserted_desc()
        |> ParticipationQueries.preload_session()

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 2
      assert length(query.order_bys) == 1
      assert length(query.preloads) == 1
    end
  end
end
