defmodule KlassHero.Shared.Adapters.Driven.Persistence.Schemas.UndeliveredEvent do
  @moduledoc """
  Ecto schema for the `undelivered_events` dead-letter table.

  Internal to `UndeliveredEventRepository` — not a domain model. Each row records
  one integration event that delivery gave up on permanently, together with the
  consumers that never received it and the serialized envelope needed to replay it.

  Identity is `event_id`; there is no synthetic primary key and no association to
  `oban_jobs`, whose rows the Pruner deletes on a schedule of its own.
  """

  use Ecto.Schema

  @primary_key false
  schema "undelivered_events" do
    field :event_id, Ecto.UUID
    field :topic, :string
    field :payload, :map
    field :missed_consumers, {:array, :string}
    field :job_id, :integer
    field :discarded_at, :utc_datetime_usec
    field :inserted_at, :utc_datetime_usec
  end
end
