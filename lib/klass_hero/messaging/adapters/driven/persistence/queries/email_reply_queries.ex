defmodule KlassHero.Messaging.Adapters.Driven.Persistence.Queries.EmailReplyQueries do
  @moduledoc """
  Composable Ecto query builders for email replies.
  """

  import Ecto.Query

  alias KlassHero.Messaging.EmailReply

  @doc """
  Base query for email replies.
  """
  def base do
    from(r in EmailReply, as: :email_reply)
  end

  @doc """
  Filter by email reply ID.
  """
  def by_id(query, id) do
    where(query, [email_reply: r], r.id == ^id)
  end

  @doc """
  Filter by inbound email ID.
  """
  def by_email(query, inbound_email_id) do
    where(query, [email_reply: r], r.inbound_email_id == ^inbound_email_id)
  end

  @doc """
  Order by inserted_at ascending (oldest first).
  Secondary sort by id for deterministic ordering when timestamps match.
  """
  def order_by_oldest(query) do
    order_by(query, [email_reply: r], asc: r.inserted_at, asc: r.id)
  end
end
