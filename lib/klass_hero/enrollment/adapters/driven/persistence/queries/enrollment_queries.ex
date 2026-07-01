defmodule KlassHero.Enrollment.Adapters.Driven.Persistence.Queries.EnrollmentQueries do
  @moduledoc """
  Composable Ecto queries for the enrollments table.

  This module provides reusable query builders that can be composed
  together for various enrollment retrieval patterns.
  """

  import Ecto.Query

  alias KlassHero.Enrollment.Enrollment

  @active_statuses ~w(pending confirmed)

  @doc """
  Returns the base query for enrollments.
  """
  @spec base() :: Ecto.Query.t()
  def base do
    from(e in Enrollment)
  end

  @doc """
  Filters enrollments by parent ID.
  """
  @spec by_parent(Ecto.Query.t(), binary()) :: Ecto.Query.t()
  def by_parent(query, parent_id) do
    where(query, [e], e.parent_id == ^parent_id)
  end

  @doc """
  Filters enrollments by child ID.
  """
  @spec by_child(Ecto.Query.t(), binary()) :: Ecto.Query.t()
  def by_child(query, child_id) do
    where(query, [e], e.child_id == ^child_id)
  end

  @doc """
  Filters enrollments by program ID.
  """
  @spec by_program(Ecto.Query.t(), binary()) :: Ecto.Query.t()
  def by_program(query, program_id) do
    where(query, [e], e.program_id == ^program_id)
  end

  @doc """
  Filters enrollments by status.
  """
  @spec by_status(Ecto.Query.t(), String.t() | [String.t()]) :: Ecto.Query.t()
  def by_status(query, statuses) when is_list(statuses) do
    where(query, [e], e.status in ^statuses)
  end

  def by_status(query, status) when is_binary(status) do
    where(query, [e], e.status == ^status)
  end

  @doc """
  Filters enrollments to only active ones (pending or confirmed).
  """
  @spec active_only(Ecto.Query.t()) :: Ecto.Query.t()
  def active_only(query) do
    by_status(query, @active_statuses)
  end

  @doc """
  Filters enrollments by enrolled_at date range.

  The range is inclusive on both ends.
  """
  @spec by_date_range(Ecto.Query.t(), Date.t(), Date.t()) :: Ecto.Query.t()
  def by_date_range(query, start_date, end_date) do
    start_datetime = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_datetime = DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")

    query
    |> where([e], e.enrolled_at >= ^start_datetime)
    |> where([e], e.enrolled_at <= ^end_datetime)
  end

  @doc """
  Orders enrollments by enrolled_at descending (most recent first).
  """
  @spec order_by_enrolled_at_desc(Ecto.Query.t()) :: Ecto.Query.t()
  def order_by_enrolled_at_desc(query) do
    order_by(query, [e], desc: e.enrolled_at)
  end

  @doc """
  Returns the count of records matching the query.
  """
  @spec count(Ecto.Query.t()) :: Ecto.Query.t()
  def count(query) do
    select(query, [e], count(e.id))
  end
end
