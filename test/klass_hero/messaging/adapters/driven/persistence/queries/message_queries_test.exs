defmodule KlassHero.Messaging.Adapters.Driven.Persistence.Queries.MessageQueriesTest do
  @moduledoc """
  Tests for MessageQueries composable query functions.

  Tests verify the query builder pattern where each function returns
  an Ecto.Query that can be piped into other query functions.
  No DB execution required — query shape is inspected directly.
  """

  use KlassHero.DataCase, async: true

  alias KlassHero.Messaging.Adapters.Driven.Persistence.Queries.MessageQueries
  alias KlassHero.Messaging.Message

  describe "base/0" do
    test "returns base query for Message" do
      query = MessageQueries.base()

      assert %Ecto.Query{} = query
      assert query.from.source == {"messages", Message}
    end
  end

  describe "by_id/2" do
    test "adds WHERE clause for message ID" do
      id = Ecto.UUID.generate()

      query =
        MessageQueries.base()
        |> MessageQueries.by_id(id)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "by_conversation/2" do
    test "adds WHERE clause for conversation ID" do
      conversation_id = Ecto.UUID.generate()

      query =
        MessageQueries.base()
        |> MessageQueries.by_conversation(conversation_id)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "not_deleted/1" do
    test "adds WHERE IS NULL clause for deleted_at" do
      query =
        MessageQueries.base()
        |> MessageQueries.not_deleted()

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "before/2" do
    test "returns query with no additional WHERE when timestamp is nil" do
      query =
        MessageQueries.base()
        |> MessageQueries.before(nil)

      assert %Ecto.Query{} = query
      assert Enum.empty?(query.wheres)
    end

    test "adds WHERE clause when timestamp is given" do
      timestamp = ~U[2025-06-01 00:00:00Z]

      query =
        MessageQueries.base()
        |> MessageQueries.before(timestamp)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "after_timestamp/2" do
    test "returns query with no additional WHERE when timestamp is nil" do
      query =
        MessageQueries.base()
        |> MessageQueries.after_timestamp(nil)

      assert %Ecto.Query{} = query
      assert Enum.empty?(query.wheres)
    end

    test "adds WHERE clause when timestamp is given" do
      timestamp = ~U[2025-06-01 00:00:00Z]

      query =
        MessageQueries.base()
        |> MessageQueries.after_timestamp(timestamp)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "order_by_newest/1" do
    test "adds ORDER BY inserted_at DESC clause" do
      query =
        MessageQueries.base()
        |> MessageQueries.order_by_newest()

      assert %Ecto.Query{} = query
      assert length(query.order_bys) == 1
    end
  end

  describe "order_by_oldest/1" do
    test "adds ORDER BY inserted_at ASC clause" do
      query =
        MessageQueries.base()
        |> MessageQueries.order_by_oldest()

      assert %Ecto.Query{} = query
      assert length(query.order_bys) == 1
    end
  end

  describe "latest_for_conversation/1" do
    test "returns base query filtered by conversation, not deleted, ordered newest, limited to 1" do
      conversation_id = Ecto.UUID.generate()

      query = MessageQueries.latest_for_conversation(conversation_id)

      assert %Ecto.Query{} = query
      assert query.from.source == {"messages", Message}
      # by_conversation and not_deleted each add 1 where
      assert length(query.wheres) == 2
      assert length(query.order_bys) == 1
      assert query.limit != nil
    end
  end

  describe "count_unread/2" do
    test "counts all non-deleted messages in conversation when last_read_at is nil" do
      conversation_id = Ecto.UUID.generate()

      query = MessageQueries.count_unread(conversation_id, nil)

      assert %Ecto.Query{} = query
      # by_conversation + not_deleted
      assert length(query.wheres) == 2
      assert query.select != nil
    end

    test "counts messages after last_read_at when timestamp is given" do
      conversation_id = Ecto.UUID.generate()
      last_read_at = ~U[2025-06-01 12:00:00Z]

      query = MessageQueries.count_unread(conversation_id, last_read_at)

      assert %Ecto.Query{} = query
      # by_conversation + not_deleted + after_timestamp
      assert length(query.wheres) == 3
      assert query.select != nil
    end
  end

  describe "paginate/2" do
    test "applies limit+1 with no timestamp filters when opts are empty" do
      query =
        MessageQueries.base()
        |> MessageQueries.paginate([])

      assert %Ecto.Query{} = query
      assert query.limit != nil
      assert Enum.empty?(query.wheres)
    end

    test "applies before timestamp filter when :before opt is given" do
      timestamp = ~U[2025-06-01 00:00:00Z]

      query =
        MessageQueries.base()
        |> MessageQueries.paginate(before: timestamp)

      assert %Ecto.Query{} = query
      assert query.limit != nil
      assert length(query.wheres) == 1
    end

    test "applies after timestamp filter when :after opt is given" do
      timestamp = ~U[2025-06-01 00:00:00Z]

      query =
        MessageQueries.base()
        |> MessageQueries.paginate(after: timestamp)

      assert %Ecto.Query{} = query
      assert query.limit != nil
      assert length(query.wheres) == 1
    end
  end

  describe "preload_assocs/2" do
    test "returns query with no preloads for empty list" do
      query =
        MessageQueries.base()
        |> MessageQueries.preload_assocs([])

      assert %Ecto.Query{} = query
      assert Enum.empty?(query.preloads)
    end

    test "adds preloads for non-empty list" do
      query =
        MessageQueries.base()
        |> MessageQueries.preload_assocs([:sender])

      assert %Ecto.Query{} = query
      assert length(query.preloads) == 1
    end
  end

  describe "query composition" do
    test "can compose filters and ordering for message listing" do
      conversation_id = Ecto.UUID.generate()
      before_ts = ~U[2025-07-01 00:00:00Z]

      query =
        MessageQueries.base()
        |> MessageQueries.by_conversation(conversation_id)
        |> MessageQueries.not_deleted()
        |> MessageQueries.before(before_ts)
        |> MessageQueries.order_by_newest()

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 3
      assert length(query.order_bys) == 1
    end

    test "can compose filters with pagination" do
      conversation_id = Ecto.UUID.generate()

      query =
        MessageQueries.base()
        |> MessageQueries.by_conversation(conversation_id)
        |> MessageQueries.not_deleted()
        |> MessageQueries.order_by_oldest()
        |> MessageQueries.paginate(limit: 25)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 2
      assert length(query.order_bys) == 1
      assert query.limit != nil
    end
  end
end
