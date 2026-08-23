defmodule KlassHero.Participation.Adapters.Driven.Persistence.Queries.SessionNoteQueriesTest do
  @moduledoc """
  Tests for SessionNoteQueries composable query functions.

  Tests verify the query builder pattern where each function returns
  an Ecto.Query that can be piped into other query functions.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Participation.Adapters.Driven.Persistence.Queries.SessionNoteQueries
  alias KlassHero.Participation.SessionNote

  describe "base/0" do
    test "returns base query for SessionNote" do
      query = SessionNoteQueries.base()

      assert %Ecto.Query{} = query
      assert query.from.source == {"session_notes", SessionNote}
    end
  end

  describe "by_participation_record/2" do
    test "adds WHERE clause for participation record ID" do
      record_id = Ecto.UUID.generate()

      query =
        SessionNoteQueries.base()
        |> SessionNoteQueries.by_participation_record(record_id)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "by_child/2" do
    test "adds WHERE clause for child ID" do
      child_id = Ecto.UUID.generate()

      query =
        SessionNoteQueries.base()
        |> SessionNoteQueries.by_child(child_id)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "by_children/2" do
    test "adds WHERE clause for child IDs" do
      child_ids = [Ecto.UUID.generate(), Ecto.UUID.generate()]

      query =
        SessionNoteQueries.base()
        |> SessionNoteQueries.by_children(child_ids)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end

    test "filters to notes belonging to one of several children" do
      included_child = insert(:child_schema)
      other_included_child = insert(:child_schema)
      excluded_child = insert(:child_schema)

      included_note = insert(:session_note_schema, child_id: included_child.id)
      other_included_note = insert(:session_note_schema, child_id: other_included_child.id)
      _excluded_note = insert(:session_note_schema, child_id: excluded_child.id)

      results =
        SessionNoteQueries.base()
        |> SessionNoteQueries.by_children([included_child.id, other_included_child.id])
        |> Repo.all()

      assert Enum.map(results, & &1.id) |> Enum.sort() ==
               Enum.sort([included_note.id, other_included_note.id])
    end

    test "excludes notes for children not in the list" do
      child = insert(:child_schema)
      unrelated_child = insert(:child_schema)

      _unrelated_note = insert(:session_note_schema, child_id: unrelated_child.id)

      results =
        SessionNoteQueries.base()
        |> SessionNoteQueries.by_children([child.id])
        |> Repo.all()

      assert results == []
    end
  end

  describe "by_status/2" do
    test "adds WHERE clause for pending_approval status" do
      query =
        SessionNoteQueries.base()
        |> SessionNoteQueries.by_status(:pending_approval)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end

    test "adds WHERE clause for approved status" do
      query =
        SessionNoteQueries.base()
        |> SessionNoteQueries.by_status(:approved)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end

    test "adds WHERE clause for rejected status" do
      query =
        SessionNoteQueries.base()
        |> SessionNoteQueries.by_status(:rejected)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "approved/1" do
    test "adds WHERE clause filtering for approved notes" do
      query =
        SessionNoteQueries.base()
        |> SessionNoteQueries.approved()

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "pending/1" do
    test "adds WHERE clause filtering for pending_approval notes" do
      query =
        SessionNoteQueries.base()
        |> SessionNoteQueries.pending()

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "order_by_submitted_desc/1" do
    test "adds ORDER BY submitted_at descending" do
      query =
        SessionNoteQueries.base()
        |> SessionNoteQueries.order_by_submitted_desc()

      assert %Ecto.Query{} = query
      assert length(query.order_bys) == 1
    end
  end

  describe "by_provider/2" do
    test "adds WHERE clause for provider ID" do
      provider_id = Ecto.UUID.generate()

      query =
        SessionNoteQueries.base()
        |> SessionNoteQueries.by_provider(provider_id)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "by_participation_records/2" do
    test "adds WHERE IN clause for multiple participation record IDs" do
      record_ids = [Ecto.UUID.generate(), Ecto.UUID.generate()]

      query =
        SessionNoteQueries.base()
        |> SessionNoteQueries.by_participation_records(record_ids)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end

    test "works with a single participation record ID in list" do
      record_ids = [Ecto.UUID.generate()]

      query =
        SessionNoteQueries.base()
        |> SessionNoteQueries.by_participation_records(record_ids)

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end

    test "works with empty list" do
      query =
        SessionNoteQueries.base()
        |> SessionNoteQueries.by_participation_records([])

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 1
    end
  end

  describe "query composition" do
    test "can compose child and status filters with ordering" do
      child_id = Ecto.UUID.generate()

      query =
        SessionNoteQueries.base()
        |> SessionNoteQueries.by_child(child_id)
        |> SessionNoteQueries.approved()
        |> SessionNoteQueries.order_by_submitted_desc()

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 2
      assert length(query.order_bys) == 1
    end

    test "can compose provider and status filters" do
      provider_id = Ecto.UUID.generate()

      query =
        SessionNoteQueries.base()
        |> SessionNoteQueries.by_provider(provider_id)
        |> SessionNoteQueries.pending()
        |> SessionNoteQueries.order_by_submitted_desc()

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 2
      assert length(query.order_bys) == 1
    end

    test "can compose participation record list filter with child and provider" do
      child_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()
      record_ids = [Ecto.UUID.generate(), Ecto.UUID.generate()]

      query =
        SessionNoteQueries.base()
        |> SessionNoteQueries.by_child(child_id)
        |> SessionNoteQueries.by_provider(provider_id)
        |> SessionNoteQueries.by_participation_records(record_ids)
        |> SessionNoteQueries.order_by_submitted_desc()

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 3
      assert length(query.order_bys) == 1
    end

    test "can compose children filter with approved shorthand" do
      child_ids = [Ecto.UUID.generate(), Ecto.UUID.generate()]

      query =
        SessionNoteQueries.base()
        |> SessionNoteQueries.by_children(child_ids)
        |> SessionNoteQueries.approved()

      assert %Ecto.Query{} = query
      assert length(query.wheres) == 2
    end
  end
end
