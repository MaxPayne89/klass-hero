defmodule KlassHero.Accounts.Domain.Ports.ForStoringUsers do
  @moduledoc """
  Port for user persistence operations in the Accounts bounded context.

  Defines the contract for user read and write operations. Read callbacks
  return domain `User.t()` structs. Write callbacks are honest about their
  Ecto coupling — LiveViews, auth plugs, and session infrastructure expect
  Ecto schemas and changesets, so the types reflect that.

  Infrastructure errors (connection, query) are not caught — they crash and
  are handled by the supervision tree.
  """

  alias KlassHero.Accounts.Domain.Models.User
  alias KlassHero.Accounts.UserToken

  @type ecto_user :: KlassHero.Accounts.User.t()
  @type ecto_changeset :: Ecto.Changeset.t()
  @type ecto_token :: UserToken.t()

  @doc "Retrieves a user by ID. Returns `{:ok, User.t()}` or `{:error, :not_found}`."
  @callback get_by_id(binary()) :: {:ok, User.t()} | {:error, :not_found}

  @doc "Retrieves a user by email. Returns `{:ok, User.t()}` or `{:error, :not_found}`."
  @callback get_by_email(String.t()) :: {:ok, User.t()} | {:error, :not_found}

  @doc "Checks if a user exists with the given ID."
  @callback exists?(binary()) :: boolean()

  @doc "Registers a new user. Accepts optional `:changeset_fn` in opts."
  @callback register(map(), keyword()) :: {:ok, ecto_user()} | {:error, ecto_changeset()}

  @doc """
  Grants an additional intended role, preserving existing ones. Idempotent (ADR-0005).
  """
  @callback append_intended_role(ecto_user(), atom()) ::
              {:ok, ecto_user()} | {:error, ecto_changeset()}

  @doc """
  Revokes an intended role, preserving others. Idempotent; mirror of `append_intended_role/2` (ADR-0005, #972).
  """
  @callback remove_intended_role(ecto_user(), atom()) ::
              {:ok, ecto_user()} | {:error, ecto_changeset()}

  @doc "Anonymizes a user's PII and deletes all tokens atomically."
  @callback anonymize(ecto_user()) :: {:ok, ecto_user()} | {:error, ecto_changeset()}

  @doc """
  Applies an email change via confirmation token. Verifies, updates, and deletes change tokens atomically.
  """
  @callback apply_email_change(ecto_user(), binary()) ::
              {:ok, ecto_user()} | {:error, :invalid_token | ecto_changeset()}

  @doc """
  Resolves a magic link token to a tagged login scenario:
  - `{:ok, {:confirmed, user, token}}` - confirmed user; caller deletes token
  - `{:ok, {:unconfirmed, user}}` - unconfirmed user; use case confirms
  - `{:error, :not_found | :invalid_token | :security_violation}`
  """
  @callback resolve_magic_link(binary()) ::
              {:ok, {:confirmed, ecto_user(), ecto_token()} | {:unconfirmed, ecto_user()}}
              | {:error, :not_found | :invalid_token | :security_violation}

  @doc "Confirms a user and deletes all their tokens atomically."
  @callback confirm_and_cleanup_tokens(ecto_user()) ::
              {:ok, {ecto_user(), [ecto_token()]}} | {:error, ecto_changeset()}

  @doc "Deletes a single token record. Returns `:ok` even if already gone."
  @callback delete_token(ecto_token()) :: :ok
end
