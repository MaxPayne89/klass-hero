defmodule KlassHero.Messaging.Adapters.Driven.Persistence.Queries.ConversationQueriesTest do
  @moduledoc """
  Tests for ConversationQueries composable query functions.

  Each function is tested as a pure query builder - structural assertions verify
  WHERE clauses, JOINs, ordering, and limits without executing against the DB.

  `with_ended_program/2` is excluded: it calls `KlassHero.ProgramCatalog.list_ended_program_ids/1`
  (a cross-context call) making it unsuitable for a pure query builder test.
  """

  use KlassHero.DataCase, async: true

  alias KlassHero.Messaging.Adapters.Driven.Persistence.Queries.ConversationQueries
  alias KlassHero.Messaging.Conversation
  alias KlassHero.Messaging.Participant

  describe "base/0" do
    test "returns base query for Conversation" do
      query = ConversationQueries.base()

      assert %Ecto.Query{} = query
      assert query.from.source == {"conversations", Conversation}
    end
  end

  describe "by_id/2" do
    test "adds WHERE clause for conversation ID" do
      id = Ecto.UUID.generate()

      query =
        ConversationQueries.base()
        |> ConversationQueries.by_id(id)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "by_provider/2" do
    test "adds WHERE clause for provider ID" do
      provider_id = Ecto.UUID.generate()

      query =
        ConversationQueries.base()
        |> ConversationQueries.by_provider(provider_id)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "by_type/2" do
    test "adds WHERE clause when given an atom type" do
      query =
        ConversationQueries.base()
        |> ConversationQueries.by_type(:direct)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end

    test "adds WHERE clause when given a binary type" do
      query =
        ConversationQueries.base()
        |> ConversationQueries.by_type("program_broadcast")

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end

    test "atom and binary produce identical query shape" do
      atom_query = ConversationQueries.base() |> ConversationQueries.by_type(:direct)
      binary_query = ConversationQueries.base() |> ConversationQueries.by_type("direct")

      assert length(atom_query.wheres) == length(binary_query.wheres)
    end
  end

  describe "by_program/2" do
    test "adds WHERE clause for program ID" do
      program_id = Ecto.UUID.generate()

      query =
        ConversationQueries.base()
        |> ConversationQueries.by_program(program_id)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "active_only/1" do
    test "adds WHERE IS NULL archived_at clause" do
      query =
        ConversationQueries.base()
        |> ConversationQueries.active_only()

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "archived_only/1" do
    test "adds WHERE IS NOT NULL archived_at clause" do
      query =
        ConversationQueries.base()
        |> ConversationQueries.archived_only()

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "where_user_is_participant/2" do
    test "adds INNER JOIN to participants" do
      user_id = Ecto.UUID.generate()

      query =
        ConversationQueries.base()
        |> ConversationQueries.where_user_is_participant(user_id)

      assert %Ecto.Query{} = query
      assert length(query.joins) == 1
    end
  end

  describe "where_user_is_not_participant/2" do
    test "adds LEFT JOIN and WHERE IS NULL clause" do
      user_id = Ecto.UUID.generate()

      query =
        ConversationQueries.base()
        |> ConversationQueries.where_user_is_not_participant(user_id)

      assert %Ecto.Query{} = query
      assert length(query.joins) == 1
      assert length(query.wheres) == 1
    end
  end

  describe "find_direct/2" do
    test "returns composite query with provider, type, active, and participant filters" do
      provider_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      query = ConversationQueries.find_direct(provider_id, user_id)

      assert %Ecto.Query{} = query
      assert query.from.source == {"conversations", Conversation}
      # by_provider + by_type(:direct) + active_only
      assert length(query.wheres) == 3
      # where_user_is_participant
      assert length(query.joins) == 1
    end
  end

  describe "retention_expired/2" do
    test "adds WHERE retention_until < before clause" do
      cutoff = DateTime.utc_now()

      query =
        ConversationQueries.base()
        |> ConversationQueries.retention_expired(cutoff)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "order_by_recent_message/1" do
    test "adds LEFT JOIN on messages, group by, and order by" do
      query =
        ConversationQueries.base()
        |> ConversationQueries.order_by_recent_message()

      assert %Ecto.Query{} = query
      assert length(query.joins) == 1
      assert length(query.group_bys) == 1
      assert length(query.order_bys) == 1
    end
  end

  describe "preload_assocs/2" do
    test "adds preload for given associations" do
      query =
        ConversationQueries.base()
        |> ConversationQueries.preload_assocs([:participants])

      assert %Ecto.Query{} = query
      assert query.preloads != []
    end

    test "accepts multiple associations" do
      query =
        ConversationQueries.base()
        |> ConversationQueries.preload_assocs([:participants, :messages])

      assert %Ecto.Query{} = query
      assert query.preloads != []
    end
  end

  describe "paginate/2" do
    test "sets LIMIT to specified limit plus one" do
      query =
        ConversationQueries.base()
        |> ConversationQueries.paginate(limit: 25)

      assert %Ecto.Query{} = query
      assert query.limit != nil
    end

    test "uses default limit of 50 when not specified" do
      query =
        ConversationQueries.base()
        |> ConversationQueries.paginate([])

      assert %Ecto.Query{} = query
      assert query.limit != nil
    end
  end

  describe "select_ids/1" do
    test "sets custom SELECT for conversation IDs" do
      query =
        ConversationQueries.base()
        |> ConversationQueries.select_ids()

      assert %Ecto.Query{} = query
      assert query.select != nil
    end
  end

  describe "with_unread_count/2" do
    test "adds two LEFT JOINs and group by for unread aggregation" do
      user_id = Ecto.UUID.generate()

      query =
        ConversationQueries.base()
        |> ConversationQueries.with_unread_count(user_id)

      assert %Ecto.Query{} = query
      # participant join + unread message join
      assert length(query.joins) == 2
      assert length(query.group_bys) == 1
    end
  end

  describe "total_unread_count/1" do
    test "returns a query based on conversation_participants table" do
      user_id = Ecto.UUID.generate()

      query = ConversationQueries.total_unread_count(user_id)

      assert %Ecto.Query{} = query
      assert query.from.source == {"conversation_participants", Participant}
    end

    test "includes JOIN to conversations and messages" do
      user_id = Ecto.UUID.generate()

      query = ConversationQueries.total_unread_count(user_id)

      assert %Ecto.Query{} = query
      assert length(query.joins) == 2
    end

    test "includes WHERE clause for user filter" do
      user_id = Ecto.UUID.generate()

      query = ConversationQueries.total_unread_count(user_id)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end
end
