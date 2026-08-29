defmodule KlassHero.Messaging.Queries.ConversationQueriesTest do
  @moduledoc """
  Tests for ConversationQueries composable query functions.

  Each function is tested as a pure query builder - structural assertions verify
  WHERE clauses, JOINs, ordering, and limits without executing against the DB.

  `with_ended_program/2` is excluded: it calls `KlassHero.ProgramCatalog.list_ended_program_ids/1`
  (a cross-context call) making it unsuitable for a pure query builder test.
  """

  use KlassHero.DataCase, async: true

  alias KlassHero.Messaging.Conversation
  alias KlassHero.Messaging.Queries.ConversationQueries

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

  describe "between_principals/3" do
    test "matches the pair in either argument order" do
      a = "00000000-0000-0000-0000-00000000000a"
      b = "00000000-0000-0000-0000-00000000000b"

      assert inspect(ConversationQueries.between_principals(a, b)) ==
               inspect(ConversationQueries.between_principals(b, a))
    end
  end

  describe "find_direct/3" do
    test "filters on provider, type, active, and the principal pair" do
      provider_id = Ecto.UUID.generate()
      user_a = Ecto.UUID.generate()
      user_b = Ecto.UUID.generate()

      query = ConversationQueries.find_direct(provider_id, user_a, user_b)

      assert %Ecto.Query{} = query
      assert query.from.source == {"conversations", Conversation}
      # by_provider + by_type(:direct) + active_only + between_principals
      assert length(query.wheres) == 4
      # Identity is a column pair now, so no participant join is needed. That is
      # the point: a membership join could never tell a provider-staff thread
      # from a parent thread the staff member happens to sit in.
      assert query.joins == []
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

  describe "select_ids/1" do
    test "sets custom SELECT for conversation IDs" do
      query =
        ConversationQueries.base()
        |> ConversationQueries.select_ids()

      assert %Ecto.Query{} = query
      assert {{:., _, [{:&, _, [0]}, :id]}, _, _} = query.select.expr
    end
  end

  # `total_unread_count/1` had three tests here asserting query *shape* — the source
  # table, `length(query.joins) == 2`, `length(query.wheres) == 1`. All three passed
  # throughout #1513's lifetime and would have passed after its fix, because none of
  # them ran the query. Behaviour coverage lives in
  # `test/klass_hero/messaging/get_total_unread_count_test.exs`.
end
