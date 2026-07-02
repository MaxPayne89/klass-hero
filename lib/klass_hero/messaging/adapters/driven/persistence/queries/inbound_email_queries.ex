defmodule KlassHero.Messaging.Adapters.Driven.Persistence.Queries.InboundEmailQueries do
  @moduledoc """
  Composable Ecto query builders for inbound emails.
  """

  import Ecto.Query

  alias KlassHero.Messaging.InboundEmail

  @doc """
  Base query for inbound emails.
  """
  def base do
    from(e in InboundEmail, as: :inbound_email)
  end

  @doc """
  Filter by inbound email ID.
  """
  def by_id(query, id) do
    where(query, [inbound_email: e], e.id == ^id)
  end

  @doc """
  Filter by Resend webhook ID.
  """
  def by_resend_id(query, resend_id) do
    where(query, [inbound_email: e], e.resend_id == ^resend_id)
  end

  @doc """
  Filter by status. Accepts nil to skip filtering (return all).
  """
  def by_status(query, nil), do: query

  def by_status(query, status) do
    status_string = to_string(status)
    where(query, [inbound_email: e], e.status == ^status_string)
  end

  @doc """
  Order by received_at descending (newest first).
  Secondary sort by id for deterministic ordering when timestamps match.
  """
  def order_by_newest(query) do
    order_by(query, [inbound_email: e], desc: e.received_at, desc: e.id)
  end

  @doc """
  Apply cursor pagination with limit.
  Fetches limit + 1 records to determine if more pages exist.
  """
  def paginate(query, opts) do
    limit = Keyword.get(opts, :limit, 50)
    before_ts = Keyword.get(opts, :before)

    query
    |> before(before_ts)
    |> limit(^(limit + 1))
  end

  @doc """
  Filter emails before a timestamp (for cursor pagination).
  """
  def before(query, nil), do: query

  def before(query, timestamp) do
    where(query, [inbound_email: e], e.received_at < ^timestamp)
  end

  @doc """
  Count emails with a given status.
  """
  def count_by_status(status) do
    status_string = to_string(status)

    base()
    |> where([inbound_email: e], e.status == ^status_string)
    |> select([inbound_email: e], count(e.id))
  end
end
