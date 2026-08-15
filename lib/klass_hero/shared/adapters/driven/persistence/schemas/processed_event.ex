defmodule KlassHero.Shared.Adapters.Driven.Persistence.Schemas.ProcessedEvent do
  @moduledoc """
  Ecto schema for the processed_events idempotency table.

  Internal to EventDispatcher — not a domain model. Each row records
  that a specific handler has processed a specific event, preventing duplicate
  execution across PubSub and Oban delivery paths.
  """

  use Ecto.Schema

  @primary_key false
  schema "processed_events" do
    field :event_id, Ecto.UUID
    field :handler_ref, :string
    field :processed_at, :utc_datetime_usec
  end
end
