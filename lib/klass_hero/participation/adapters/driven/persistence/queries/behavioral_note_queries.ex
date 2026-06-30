defmodule KlassHero.Participation.Adapters.Driven.Persistence.Queries.BehavioralNoteQueries do
  @moduledoc """
  Composable Ecto query functions for behavioral notes.

  Follows Pattern 2: Query Builders - Compose Queries with Functions.
  Each function returns an Ecto query that can be piped into others.
  """

  import Ecto.Query

  alias KlassHero.Participation.BehavioralNote

  @doc "Base query for behavioral notes."
  @spec base() :: Ecto.Query.t()
  def base do
    from(n in BehavioralNote, as: :note)
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

  @doc "Filters by parent ID."
  @spec by_parent(Ecto.Query.t(), String.t()) :: Ecto.Query.t()
  def by_parent(query, parent_id) do
    where(query, [note: n], n.parent_id == ^parent_id)
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
