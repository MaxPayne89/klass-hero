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
  # Write operations return Ecto types because callers (LiveViews, auth plugs)
  # depend on Ecto schemas for rendering and session management.
  alias KlassHero.Accounts.UserToken

  @type ecto_user :: KlassHero.Accounts.User.t()
  @type ecto_changeset :: Ecto.Changeset.t()
  @type ecto_token :: UserToken.t()

  # ============================================================================
  # Read operations
  # ============================================================================

  @doc """
  Retrieves a user by their unique identifier.

  Returns:
  - `{:ok, User.t()}` - User found
  - `{:error, :not_found}` - No user with this ID
  """
  @callback get_by_id(binary()) :: {:ok, User.t()} | {:error, :not_found}

  @doc """
  Retrieves a user by email address.

  Returns:
  - `{:ok, User.t()}` - User found
  - `{:error, :not_found}` - No user with this email
  """
  @callback get_by_email(String.t()) :: {:ok, User.t()} | {:error, :not_found}

  @doc """
  Checks if a user exists with the given ID.
  """
  @callback exists?(binary()) :: boolean()

  # ============================================================================
  # Write operations
  # ============================================================================

  @doc """
  Registers a new user from the given attributes.

  Accepts optional keyword opts for customization (e.g., `:changeset_fn`).

  Returns:
  - `{:ok, ecto_user()}` - User created
  - `{:error, ecto_changeset()}` - Validation or persistence failure
  """
  @callback register(map(), keyword()) :: {:ok, ecto_user()} | {:error, ecto_changeset()}

  @doc """
  Grants an additional intended role to a user, preserving existing roles.

  Idempotent — adding a role the user already holds is a no-op. Used when an
  existing account is linked as staff (ADR-0005 multi-persona).

  Returns:
  - `{:ok, ecto_user()}` - Updated user
  - `{:error, ecto_changeset()}` - Update failure
  """
  @callback append_intended_role(ecto_user(), atom()) ::
              {:ok, ecto_user()} | {:error, ecto_changeset()}

  @doc """
  Anonymizes a user's PII and deletes all their tokens atomically.

  Returns:
  - `{:ok, ecto_user()}` - Anonymized user
  - `{:error, ecto_changeset()}` - Update failure
  """
  @callback anonymize(ecto_user()) :: {:ok, ecto_user()} | {:error, ecto_changeset()}

  @doc """
  Applies an email change using a confirmation token.

  Verifies the token, updates the email, and deletes all change tokens
  for the context atomically.

  Returns:
  - `{:ok, ecto_user()}` - Updated user
  - `{:error, :invalid_token}` - Token malformed, expired, or not found
  - `{:error, ecto_changeset()}` - Update failure
  """
  @callback apply_email_change(ecto_user(), binary()) ::
              {:ok, ecto_user()} | {:error, :invalid_token | ecto_changeset()}

  @doc """
  Resolves a magic link token to a user and determines login scenario.

  Returns tagged tuples to distinguish business cases:
  - `{:ok, {:confirmed, user, token}}` - Already-confirmed user, token to delete
  - `{:ok, {:unconfirmed, user}}` - Unconfirmed user needing confirmation
  - `{:error, :not_found}` - Token invalid or expired
  - `{:error, :invalid_token}` - Token malformed (bad base64)
  - `{:error, :security_violation}` - Unconfirmed user with password set
  """
  @callback resolve_magic_link(binary()) ::
              {:ok, {:confirmed, ecto_user(), ecto_token()} | {:unconfirmed, ecto_user()}}
              | {:error, :not_found | :invalid_token | :security_violation}

  @doc """
  Confirms a user and deletes all their tokens atomically.

  Used after resolving a magic link for an unconfirmed user.

  Returns:
  - `{:ok, {ecto_user(), [ecto_token()]}}` - Confirmed user + deleted tokens
  - `{:error, ecto_changeset()}` - Update failure
  """
  @callback confirm_and_cleanup_tokens(ecto_user()) ::
              {:ok, {ecto_user(), [ecto_token()]}} | {:error, ecto_changeset()}

  @doc """
  Deletes a single token record.

  Used to expire a magic link token after successful login for confirmed users.

  Returns:
  - `:ok` - Token deleted (or already gone)
  """
  @callback delete_token(ecto_token()) :: :ok
end
