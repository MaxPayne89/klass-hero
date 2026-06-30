defmodule KlassHero.Participation.Adapters.Driven.Persistence.Queries.BehavioralNoteQueriesTest do
  @moduledoc """
  Tests for BehavioralNoteQueries composable query functions.

  Tests verify the query builder pattern where each function returns
  an Ecto.Query that can be piped into other query functions.
  """

  use KlassHero.DataCase, async: true

  alias KlassHero.Participation.Adapters.Driven.Persistence.Queries.BehavioralNoteQueries
  alias KlassHero.Participation.BehavioralNote

  describe "base/0" do
    test "returns base query for BehavioralNote" do
      query = BehavioralNoteQueries.base()

      assert %Ecto.Query{} = query
      assert query.from.source == {"behavioral_notes", BehavioralNote}
    end
  end

  describe "by_participation_record/2" do
    test "adds WHERE clause for participation record ID" do
      record_id = Ecto.UUID.generate()

      query =
        BehavioralNoteQueries.base()
        |> BehavioralNoteQueries.by_participation_record(record_id)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "by_child/2" do
    test "adds WHERE clause for child ID" do
      child_id = Ecto.UUID.generate()

      query =
        BehavioralNoteQueries.base()
        |> BehavioralNoteQueries.by_child(child_id)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "by_parent/2" do
    test "adds WHERE clause for parent ID" do
      parent_id = Ecto.UUID.generate()

      query =
        BehavioralNoteQueries.base()
        |> BehavioralNoteQueries.by_parent(parent_id)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "by_status/2" do
    test "adds WHERE clause for pending_approval status" do
      query =
        BehavioralNoteQueries.base()
        |> BehavioralNoteQueries.by_status(:pending_approval)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end

    test "adds WHERE clause for approved status" do
      query =
        BehavioralNoteQueries.base()
        |> BehavioralNoteQueries.by_status(:approved)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end

    test "adds WHERE clause for rejected status" do
      query =
        BehavioralNoteQueries.base()
        |> BehavioralNoteQueries.by_status(:rejected)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "approved/1" do
    test "adds WHERE clause filtering for approved notes" do
      query =
        BehavioralNoteQueries.base()
        |> BehavioralNoteQueries.approved()

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "pending/1" do
    test "adds WHERE clause filtering for pending_approval notes" do
      query =
        BehavioralNoteQueries.base()
        |> BehavioralNoteQueries.pending()

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "order_by_submitted_desc/1" do
    test "adds ORDER BY submitted_at descending" do
      query =
        BehavioralNoteQueries.base()
        |> BehavioralNoteQueries.order_by_submitted_desc()

      assert %Ecto.Query{} = query
      assert length(query.order_bys) == 1
    end
  end

  describe "by_provider/2" do
    test "adds WHERE clause for provider ID" do
      provider_id = Ecto.UUID.generate()

      query =
        BehavioralNoteQueries.base()
        |> BehavioralNoteQueries.by_provider(provider_id)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "by_participation_records/2" do
    test "adds WHERE IN clause for multiple participation record IDs" do
      record_ids = [Ecto.UUID.generate(), Ecto.UUID.generate()]

      query =
        BehavioralNoteQueries.base()
        |> BehavioralNoteQueries.by_participation_records(record_ids)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end

    test "works with a single participation record ID in list" do
      record_ids = [Ecto.UUID.generate()]

      query =
        BehavioralNoteQueries.base()
        |> BehavioralNoteQueries.by_participation_records(record_ids)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end

    test "works with empty list" do
      query =
        BehavioralNoteQueries.base()
        |> BehavioralNoteQueries.by_participation_records([])

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "query composition" do
    test "can compose child and status filters with ordering" do
      child_id = Ecto.UUID.generate()

      query =
        BehavioralNoteQueries.base()
        |> BehavioralNoteQueries.by_child(child_id)
        |> BehavioralNoteQueries.approved()
        |> BehavioralNoteQueries.order_by_submitted_desc()

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 2
      assert length(query.order_bys) == 1
    end

    test "can compose provider and status filters" do
      provider_id = Ecto.UUID.generate()

      query =
        BehavioralNoteQueries.base()
        |> BehavioralNoteQueries.by_provider(provider_id)
        |> BehavioralNoteQueries.pending()
        |> BehavioralNoteQueries.order_by_submitted_desc()

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 2
      assert length(query.order_bys) == 1
    end

    test "can compose participation record list filter with child and provider" do
      child_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()
      record_ids = [Ecto.UUID.generate(), Ecto.UUID.generate()]

      query =
        BehavioralNoteQueries.base()
        |> BehavioralNoteQueries.by_child(child_id)
        |> BehavioralNoteQueries.by_provider(provider_id)
        |> BehavioralNoteQueries.by_participation_records(record_ids)
        |> BehavioralNoteQueries.order_by_submitted_desc()

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 3
      assert length(query.order_bys) == 1
    end

    test "can compose parent filter with approved shorthand" do
      parent_id = Ecto.UUID.generate()

      query =
        BehavioralNoteQueries.base()
        |> BehavioralNoteQueries.by_parent(parent_id)
        |> BehavioralNoteQueries.approved()

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 2
    end
  end
end
