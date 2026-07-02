defmodule KlassHero.Messaging.Adapters.Driven.Persistence.Queries.EmailReplyQueriesTest do
  @moduledoc """
  Tests for EmailReplyQueries composable query functions.

  Tests verify the query builder pattern where each function returns
  an Ecto.Query that can be piped into other query functions.
  No DB execution required — query shape is inspected directly.
  """

  use KlassHero.DataCase, async: true

  alias KlassHero.Messaging.Adapters.Driven.Persistence.Queries.EmailReplyQueries
  alias KlassHero.Messaging.EmailReply

  describe "base/0" do
    test "returns base query for EmailReply" do
      query = EmailReplyQueries.base()

      assert %Ecto.Query{} = query
      assert query.from.source == {"email_replies", EmailReply}
    end
  end

  describe "by_id/2" do
    test "adds WHERE clause for email reply ID" do
      id = Ecto.UUID.generate()

      query =
        EmailReplyQueries.base()
        |> EmailReplyQueries.by_id(id)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "by_email/2" do
    test "adds WHERE clause for inbound email ID" do
      inbound_email_id = Ecto.UUID.generate()

      query =
        EmailReplyQueries.base()
        |> EmailReplyQueries.by_email(inbound_email_id)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "order_by_oldest/1" do
    test "adds ORDER BY inserted_at ASC clause" do
      query =
        EmailReplyQueries.base()
        |> EmailReplyQueries.order_by_oldest()

      assert %Ecto.Query{} = query
      assert length(query.order_bys) == 1
    end
  end

  describe "query composition" do
    test "can compose email filter with ordering for reply listing" do
      inbound_email_id = Ecto.UUID.generate()

      query =
        EmailReplyQueries.base()
        |> EmailReplyQueries.by_email(inbound_email_id)
        |> EmailReplyQueries.order_by_oldest()

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
      assert length(query.order_bys) == 1
    end
  end
end
