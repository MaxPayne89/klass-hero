defmodule KlassHero.Shared.Adapters.Driven.Persistence.Schemas.UndeliveredEvent do
  @moduledoc """
  Ecto schema for the `undelivered_events` dead-letter table.

  Not a domain model. Each row records one integration event that delivery gave up
  on permanently, together with the consumers that never received it and the
  serialized envelope needed to replay it.

  Written and pruned only through `UndeliveredEventRepository`. It is also read
  directly by `KlassHeroWeb.Admin.UndeliveredEventLive`, which is a Backpex
  LiveResource and so operates on the schema and Repo by design — the same
  admin-only exception the other admin resources take.

  Identity is `event_id`; there is no synthetic primary key and no association to
  `oban_jobs`, whose rows the Pruner deletes on a schedule of its own.

  `event_id` is declared `:binary_id` rather than `Ecto.UUID` — the same value at
  the database, but Backpex only special-cases `:id` and `:binary_id` when casting
  a URL segment into the show query. Under any other type a typo'd admin link
  reaches the catch-all and raises `Ecto.Query.CastError` (a 500) where it should
  simply not be found.
  """

  use Ecto.Schema

  @primary_key false
  schema "undelivered_events" do
    field :event_id, :binary_id
    field :topic, :string
    field :payload, :map
    field :missed_consumers, {:array, :string}
    field :job_id, :integer
    field :discarded_at, :utc_datetime_usec
    field :inserted_at, :utc_datetime_usec
  end
end
