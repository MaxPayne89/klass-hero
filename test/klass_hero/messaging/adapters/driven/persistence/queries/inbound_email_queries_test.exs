defmodule KlassHero.Messaging.Adapters.Driven.Persistence.Queries.InboundEmailQueriesTest do
  @moduledoc """
  Tests for InboundEmailQueries composable query functions.

  Tests verify the query builder pattern where each function returns
  an Ecto.Query that can be piped into other query functions.
  No DB execution required — query shape is inspected directly.
  """

  use KlassHero.DataCase, async: true

  alias KlassHero.Messaging.Adapters.Driven.Persistence.Queries.InboundEmailQueries
  alias KlassHero.Messaging.InboundEmail

  describe "base/0" do
    test "returns base query for InboundEmail" do
      query = InboundEmailQueries.base()

      assert %Ecto.Query{} = query
      assert query.from.source == {"inbound_emails", InboundEmail}
    end
  end

  describe "by_id/2" do
    test "adds WHERE clause for inbound email ID" do
      id = Ecto.UUID.generate()

      query =
        InboundEmailQueries.base()
        |> InboundEmailQueries.by_id(id)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "by_resend_id/2" do
    test "adds WHERE clause for resend ID" do
      resend_id = "resend-#{Ecto.UUID.generate()}"

      query =
        InboundEmailQueries.base()
        |> InboundEmailQueries.by_resend_id(resend_id)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "by_status/2" do
    test "returns query with no WHERE when status is nil" do
      query =
        InboundEmailQueries.base()
        |> InboundEmailQueries.by_status(nil)

      assert %Ecto.Query{} = query
      assert Enum.empty?(query.wheres)
    end

    test "adds WHERE clause for atom status" do
      query =
        InboundEmailQueries.base()
        |> InboundEmailQueries.by_status(:unread)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end

    test "adds WHERE clause for string status" do
      query =
        InboundEmailQueries.base()
        |> InboundEmailQueries.by_status("archived")

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "order_by_newest/1" do
    test "adds ORDER BY received_at DESC clause" do
      query =
        InboundEmailQueries.base()
        |> InboundEmailQueries.order_by_newest()

      assert %Ecto.Query{} = query
      assert length(query.order_bys) == 1
    end
  end

  describe "before/2" do
    test "returns query with no WHERE when timestamp is nil" do
      query =
        InboundEmailQueries.base()
        |> InboundEmailQueries.before(nil)

      assert %Ecto.Query{} = query
      assert Enum.empty?(query.wheres)
    end

    test "adds WHERE clause when timestamp is given" do
      timestamp = ~U[2025-06-01 00:00:00Z]

      query =
        InboundEmailQueries.base()
        |> InboundEmailQueries.before(timestamp)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "paginate/2" do
    test "applies limit+1 with no timestamp filter when opts are empty" do
      query =
        InboundEmailQueries.base()
        |> InboundEmailQueries.paginate([])

      assert %Ecto.Query{} = query
      assert query.limit != nil
      assert Enum.empty?(query.wheres)
    end

    test "applies before timestamp filter when :before opt is given" do
      timestamp = ~U[2025-06-01 00:00:00Z]

      query =
        InboundEmailQueries.base()
        |> InboundEmailQueries.paginate(before: timestamp)

      assert %Ecto.Query{} = query
      assert query.limit != nil
      assert length(query.wheres) == 1
    end
  end

  describe "count_by_status/1" do
    test "returns query with base source, WHERE clause, and select" do
      query = InboundEmailQueries.count_by_status(:unread)

      assert %Ecto.Query{} = query
      assert query.from.source == {"inbound_emails", InboundEmail}
      assert length(query.wheres) == 1
      assert query.select != nil
    end

    test "accepts string status" do
      query = InboundEmailQueries.count_by_status("archived")

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "query composition" do
    test "can compose status filter with ordering and pagination" do
      timestamp = ~U[2025-06-01 00:00:00Z]

      query =
        InboundEmailQueries.base()
        |> InboundEmailQueries.by_status(:unread)
        |> InboundEmailQueries.order_by_newest()
        |> InboundEmailQueries.paginate(before: timestamp)

      assert %Ecto.Query{} = query
      # by_status + before (from paginate)
      assert length(query.wheres) == 2
      assert length(query.order_bys) == 1
      assert query.limit != nil
    end

    test "nil status filter skips WHERE clause in composition" do
      query =
        InboundEmailQueries.base()
        |> InboundEmailQueries.by_status(nil)
        |> InboundEmailQueries.order_by_newest()

      assert %Ecto.Query{} = query
      assert Enum.empty?(query.wheres)
      assert length(query.order_bys) == 1
    end
  end
end
