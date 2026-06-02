defmodule KlassHero.Family.Adapters.Driven.Persistence.Mappers.ConsentMapper do
  @moduledoc """
  Bidirectional mapping between Consent domain entities and ConsentSchema.

  Handles conversion between domain representation (string UUIDs) and
  database representation (binary UUIDs), ensuring clean separation
  between domain and infrastructure layers.
  """

  alias KlassHero.Family.Adapters.Driven.Persistence.Schemas.ConsentSchema
  alias KlassHero.Family.Domain.Models.Consent
  alias KlassHero.Shared.Adapters.Driven.Persistence.MapperHelpers

  @doc """
  Converts a ConsentSchema (from database) to a Consent domain entity.

  Routes construction through the domain model's `from_persistence/1`
  to enforce `@enforce_keys` invariants. Raises on corrupted data.
  """
  def to_domain(%ConsentSchema{} = schema) do
    attrs = %{
      id: Ecto.UUID.cast!(schema.id),
      parent_id: Ecto.UUID.cast!(schema.parent_id),
      child_id: Ecto.UUID.cast!(schema.child_id),
      consent_type: schema.consent_type,
      granted_at: schema.granted_at,
      withdrawn_at: schema.withdrawn_at,
      inserted_at: schema.inserted_at,
      updated_at: schema.updated_at
    }

    MapperHelpers.from_persistence!(Consent, attrs, schema.id)
  end
end
