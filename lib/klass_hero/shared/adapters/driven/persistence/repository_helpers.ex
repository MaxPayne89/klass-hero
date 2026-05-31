defmodule KlassHero.Shared.Adapters.Driven.Persistence.RepositoryHelpers do
  @moduledoc """
  Shared fetch-and-map helpers for repository adapters.

  Each helper delegates domain mapping to a `mapper` module implementing
  `to_domain/1`. None emit telemetry spans — callers wrap calls in their own
  `span` so traces attribute to the repository, not this module.
  """

  alias KlassHero.Repo

  @doc "Fetches by primary key and maps to a domain struct. Raises on a malformed id."
  @spec get_by_id(module(), term(), module()) :: {:ok, struct()} | {:error, :not_found}
  def get_by_id(schema, id, mapper) do
    case Repo.get(schema, id) do
      nil -> {:error, :not_found}
      record -> {:ok, mapper.to_domain(record)}
    end
  end

  @doc """
  Fetches a schema record by UUID primary key, returning `{:error, :not_found}`
  for a malformed id instead of raising.

  Uses `Ecto.UUID.dump/1`, not `cast/1`: `cast/1` accepts raw 16-byte binaries
  that are not valid textual UUIDs.
  """
  @spec get_schema_by_uuid(module(), term()) :: {:ok, struct()} | {:error, :not_found}
  def get_schema_by_uuid(schema, id) do
    case Ecto.UUID.dump(id) do
      {:ok, _binary} ->
        case Repo.get(schema, id) do
          nil -> {:error, :not_found}
          record -> {:ok, record}
        end

      :error ->
        {:error, :not_found}
    end
  end

  @doc "UUID-safe `get_by_id/3`: maps to a domain struct, `:not_found` for a malformed id."
  @spec get_by_uuid(module(), term(), module()) :: {:ok, struct()} | {:error, :not_found}
  def get_by_uuid(schema, id, mapper) do
    case get_schema_by_uuid(schema, id) do
      {:ok, record} -> {:ok, mapper.to_domain(record)}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  @doc "Runs a single-row query and maps the result."
  @spec fetch_one(Ecto.Queryable.t(), module()) :: {:ok, struct()} | {:error, :not_found}
  def fetch_one(queryable, mapper) do
    case Repo.one(queryable) do
      nil -> {:error, :not_found}
      record -> {:ok, mapper.to_domain(record)}
    end
  end
end
