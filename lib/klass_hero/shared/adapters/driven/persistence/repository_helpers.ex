defmodule KlassHero.Shared.Adapters.Driven.Persistence.RepositoryHelpers do
  @moduledoc """
  Small conveniences shared by persistence-adapter code.

  The mapper-taking fetch-and-map variants were removed post-flatten (#986→#1002)
  once every schema became its own domain struct. What remains is unrelated:

    * `get_schema_by_uuid/2` — a UUID-safe `Repo.get` that returns
      `{:error, :not_found}` for a malformed id instead of raising.
    * `insert_isolated/2` — an insert whose constraint violation stays
      recoverable whether or not a transaction is open.
    * `log_validation_error/2` — canonical changeset-failure logging.

  None emit telemetry spans; callers wrap their own `span` so traces attribute
  to the repository, not this module.
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
  Inserts a changeset whose constraint violation must come back as
  `{:error, changeset}` without damaging anything around it.

  Inside a transaction that means `mode: :savepoint`: without it the constraint
  hit aborts the *enclosing* transaction instead of being caught by the caller
  (#1065). Outside one it means the opposite — `mode: :savepoint` has no
  transaction to open a savepoint against, so Postgrex refuses and DBConnection
  raises `TransactionError` (#1322, a crash on the add-a-child flow).

  So the mode follows the actual context rather than assuming one. Note this
  cannot be tested under the SQL sandbox, which proxies every statement through
  its own savepoint and hides both failure modes — see
  `test/klass_hero/family/consents_unboxed_test.exs`.
  """
  @spec insert_isolated(Ecto.Changeset.t(), keyword()) ::
          {:ok, struct()} | {:error, Ecto.Changeset.t()}
  def insert_isolated(%Ecto.Changeset{} = changeset, opts \\ []) do
    # Merge, not `++`: a keyword lookup takes the first match, so appending would
    # let the derived mode silently outrank a caller's explicit one.
    Repo.insert(changeset, Keyword.merge(isolation_opts(), opts))
  end

  defp isolation_opts do
    if Repo.in_transaction?(), do: [mode: :savepoint], else: []
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
