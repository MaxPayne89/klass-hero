defmodule KlassHero.Shared.Adapters.Driven.Persistence.RepositoryHelpers do
  @moduledoc """
  Two small conveniences shared by persistence-adapter code.

  The mapper-taking fetch-and-map variants were removed post-flatten (#986→#1002)
  once every schema became its own domain struct. What remains is unrelated:

    * `get_schema_by_uuid/2` — a UUID-safe `Repo.get` that returns
      `{:error, :not_found}` for a malformed id instead of raising.
    * `log_validation_error/2` — canonical changeset-failure logging.

  Neither emits telemetry spans; callers wrap their own `span` so traces
  attribute to the repository, not this module.
  """

  alias KlassHero.Repo

  require Logger

  @doc """
  Fetches a schema record by UUID primary key, returning `{:error, :not_found}`
  for a malformed id instead of raising.

  Uses `Ecto.UUID.dump/1`, not `cast/1`: `cast/1` accepts raw 16-byte binaries
  that are not valid textual UUIDs.

  Accepts any `Ecto.Queryable` — pass a scoped query (e.g. `Schema.owned_by(id)`)
  to make a foreign row unreachable rather than fetched and then rejected.
  """
  @spec get_schema_by_uuid(Ecto.Queryable.t(), term()) :: {:ok, struct()} | {:error, :not_found}
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

  @doc """
  Logs a changeset validation failure in the canonical format (`error_id:` plus
  raw `errors:`), returning `:ok`. The caller keeps returning `{:error, changeset}`.
  """
  @spec log_validation_error(Ecto.Changeset.t(), String.t()) :: :ok
  def log_validation_error(%Ecto.Changeset{} = changeset, error_id) when is_binary(error_id) do
    Logger.warning("Repository validation failed",
      error_id: error_id,
      errors: changeset.errors
    )
  end
end
