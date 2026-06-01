defmodule KlassHero.Accounts.Adapters.Driven.Persistence.Mappers.UserMapper do
  @moduledoc """
  Maps between the User Ecto schema and User domain entity.

  One-directional (read path only):
  - `to_domain/1`: User schema -> Domain.Models.User

  No `to_schema/1` — use cases work with the Ecto schema directly
  for mutations, since changesets need the schema struct.
  """

  alias KlassHero.Accounts.Domain.Models.User, as: DomainUser
  alias KlassHero.Accounts.User
  alias KlassHero.Shared.Adapters.Driven.Persistence.MapperHelpers

  @doc """
  Converts a User schema (from database) to a User domain entity.

  Routes through `from_persistence/1` to enforce `@enforce_keys`.
  Raises on corrupted data.
  """
  def to_domain(%User{} = schema) do
    attrs = %{
      id: schema.id,
      email: schema.email,
      name: schema.name,
      avatar: schema.avatar,
      confirmed_at: schema.confirmed_at,
      is_admin: schema.is_admin,
      locale: schema.locale,
      intended_roles: schema.intended_roles || [],
      inserted_at: schema.inserted_at,
      updated_at: schema.updated_at
    }

    MapperHelpers.from_persistence!(DomainUser, attrs, schema.id)
  end
end
