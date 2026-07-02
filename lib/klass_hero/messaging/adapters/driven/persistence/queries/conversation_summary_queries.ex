defmodule KlassHero.Messaging.Adapters.Driven.Persistence.Queries.ConversationSummaryQueries do
  @moduledoc """
  Composable Ecto query builders for the conversation_summaries read table.

  This module provides query functions for the read side of the CQRS pattern.
  The projection GenServer handles writes; these queries serve reads.
  """

  import Ecto.Query

  alias KlassHero.Messaging.ConversationSummary

  @doc "Base query for conversation summaries."
  def base do
    from(s in ConversationSummary)
  end

  @doc "Filter by conversation ID."
  def by_conversation(query, conversation_id) do
    where(query, [s], s.conversation_id == ^conversation_id)
  end

  @doc """
  Filter to rows where the given token exists as a key in the system_notes JSONB.

  Uses the PostgreSQL `?` operator which is backed by the GIN index.
  """
  def has_system_note_key(query, token) do
    where(query, [s], fragment("? \\? ?", s.system_notes, ^token))
  end
end
