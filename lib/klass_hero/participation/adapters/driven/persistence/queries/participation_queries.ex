defmodule KlassHero.Participation.Adapters.Driven.Persistence.Queries.ParticipationQueries do
  @moduledoc """
  Composable Ecto query functions for participation records.

  Follows Pattern 2: Query Builders - Compose Queries with Functions.
  Each function returns an Ecto query that can be piped into others.
  """

  import Ecto.Query

  alias KlassHero.Participation.ParticipationRecord
  alias KlassHero.Participation.ProgramSession

  @doc "Base query for participation records."
  @spec base() :: Ecto.Query.t()
  def base do
    from(r in ParticipationRecord, as: :record)
  end

  @doc "Filters by session ID."
  @spec by_session(Ecto.Query.t(), String.t()) :: Ecto.Query.t()
  def by_session(query, session_id) do
    where(query, [record: r], r.session_id == ^session_id)
  end

  @doc "Filters by child ID."
  @spec by_child(Ecto.Query.t(), String.t()) :: Ecto.Query.t()
  def by_child(query, child_id) do
    where(query, [record: r], r.child_id == ^child_id)
  end

  @doc "Filters by multiple child IDs."
  @spec by_children(Ecto.Query.t(), [String.t()]) :: Ecto.Query.t()
  def by_children(query, child_ids) when is_list(child_ids) do
    where(query, [record: r], r.child_id in ^child_ids)
  end

  @doc "Filters by status."
  @spec by_status(Ecto.Query.t(), atom() | [atom()]) :: Ecto.Query.t()
  def by_status(query, statuses) when is_list(statuses) do
    where(query, [record: r], r.status in ^statuses)
  end

  def by_status(query, status) when is_atom(status) do
    where(query, [record: r], r.status == ^status)
  end

  @doc "Filters by date range (joins with sessions)."
  @spec by_date_range(Ecto.Query.t(), Date.t(), Date.t()) :: Ecto.Query.t()
  def by_date_range(query, start_date, end_date) do
    query
    |> join(:inner, [record: r], s in ProgramSession,
      on: r.session_id == s.id,
      as: :session
    )
    |> where([session: s], s.session_date >= ^start_date and s.session_date <= ^end_date)
  end

  @doc "Orders by session date descending (requires session join)."
  @spec order_by_session_date_desc(Ecto.Query.t()) :: Ecto.Query.t()
  def order_by_session_date_desc(query) do
    order_by(query, [session: s], desc: s.session_date, desc: s.start_time)
  end

  @doc "Orders by inserted_at descending."
  @spec order_by_inserted_desc(Ecto.Query.t()) :: Ecto.Query.t()
  def order_by_inserted_desc(query) do
    order_by(query, [record: r], desc: r.inserted_at)
  end

  @doc "Preloads session association."
  @spec preload_session(Ecto.Query.t()) :: Ecto.Query.t()
  def preload_session(query) do
    preload(query, [:session])
  end

  @doc "Limits results."
  @spec limit_results(Ecto.Query.t(), pos_integer()) :: Ecto.Query.t()
  def limit_results(query, limit) do
    limit(query, ^limit)
  end

  @doc "Selects only specific fields."
  @spec select_summary(Ecto.Query.t()) :: Ecto.Query.t()
  def select_summary(query) do
    select(query, [record: r], %{
      id: r.id,
      session_id: r.session_id,
      child_id: r.child_id,
      status: r.status,
      check_in_at: r.check_in_at,
      check_out_at: r.check_out_at
    })
  end
end
