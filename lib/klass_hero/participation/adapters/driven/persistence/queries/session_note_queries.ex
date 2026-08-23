defmodule KlassHero.Participation.Adapters.Driven.Persistence.Queries.SessionNoteQueries do
  @moduledoc """
  Composable Ecto query functions for session notes.

  Follows Pattern 2: Query Builders - Compose Queries with Functions.
  Each function returns an Ecto query that can be piped into others.
  """

  import Ecto.Query

  alias KlassHero.Participation.SessionNote

  @doc "Base query for session notes."
  @spec base() :: Ecto.Query.t()
  def base do
    from(n in SessionNote, as: :note)
  end

  @doc "Filters by participation record ID."
  @spec by_participation_record(Ecto.Query.t(), String.t()) :: Ecto.Query.t()
  def by_participation_record(query, participation_record_id) do
    where(query, [note: n], n.participation_record_id == ^participation_record_id)
  end

  @doc "Filters by child ID."
  @spec by_child(Ecto.Query.t(), String.t()) :: Ecto.Query.t()
  def by_child(query, child_id) do
    where(query, [note: n], n.child_id == ^child_id)
  end

  @doc """
  Filters to the notes about any of `child_ids`.

  This is how a parent's own notes are found. `session_notes.parent_id` looks like
  the obvious filter and is not: nothing on the write path ever populates it, so it
  is NULL on every row in production (#1329). Family owns the child→guardian
  relation, so the caller resolves the ids through its facade and passes them here.
  """
  @spec by_children(Ecto.Query.t(), [String.t()]) :: Ecto.Query.t()
  def by_children(query, child_ids) when is_list(child_ids) do
    where(query, [note: n], n.child_id in ^child_ids)
  end

  @doc "Filters by status."
  @spec by_status(Ecto.Query.t(), atom()) :: Ecto.Query.t()
  def by_status(query, status) when is_atom(status) do
    where(query, [note: n], n.status == ^status)
  end

  @doc "Filters for approved notes."
  @spec approved(Ecto.Query.t()) :: Ecto.Query.t()
  def approved(query), do: by_status(query, :approved)

  @doc "Filters for pending notes."
  @spec pending(Ecto.Query.t()) :: Ecto.Query.t()
  def pending(query), do: by_status(query, :pending_approval)

  @doc "Orders by submitted_at descending."
  @spec order_by_submitted_desc(Ecto.Query.t()) :: Ecto.Query.t()
  def order_by_submitted_desc(query) do
    order_by(query, [note: n], desc: n.submitted_at)
  end

  @doc "Filters by provider ID."
  @spec by_provider(Ecto.Query.t(), String.t()) :: Ecto.Query.t()
  def by_provider(query, provider_id) do
    where(query, [note: n], n.provider_id == ^provider_id)
  end

  @doc "Filters by multiple participation record IDs."
  @spec by_participation_records(Ecto.Query.t(), [String.t()]) :: Ecto.Query.t()
  def by_participation_records(query, record_ids) when is_list(record_ids) do
    where(query, [note: n], n.participation_record_id in ^record_ids)
  end
end
