defmodule KlassHero.Accounts.Adapters.Driven.Persistence.Repositories.UserRepository do
  @moduledoc """
  Repository implementation for user persistence.

  Implements ForStoringUsers with domain entity mapping via UserMapper
  for reads, and direct Ecto schema operations for writes.

  Write operations absorb Ecto.Multi transactions so use cases remain
  pure orchestrators. Callers receive Ecto schemas for write operations
  (LiveViews and auth plugs expect them).

  Infrastructure errors (connection, query) are not caught — they crash
  and are handled by the supervision tree.
  """

  @behaviour KlassHero.Accounts.Domain.Ports.ForStoringUsers

  use KlassHero.Shared.Tracing

  import Ecto.Query

  alias KlassHero.Accounts.Adapters.Driven.Persistence.Mappers.UserMapper
  alias KlassHero.Accounts.Adapters.Driven.Persistence.TokenCleanup
  alias KlassHero.Accounts.{User, UserToken}
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.RepositoryHelpers

  require Logger

  # ============================================================================
  # Read operations
  # ============================================================================

  @impl true
  def get_by_id(user_id) when is_binary(user_id) do
    span do
      set_attributes("db", operation: "select", entity: "user")

      RepositoryHelpers.get_by_id(User, user_id, UserMapper)
    end
  end

  @impl true
  def get_by_email(email) when is_binary(email) do
    span do
      set_attributes("db", operation: "select", entity: "user")

      case Repo.get_by(User, email: email) do
        nil -> {:error, :not_found}
        schema -> {:ok, UserMapper.to_domain(schema)}
      end
    end
  end

  @impl true
  def exists?(user_id) when is_binary(user_id) do
    span do
      set_attributes("db", operation: "select", entity: "user")

      User
      |> where([u], u.id == ^user_id)
      |> Repo.exists?()
    end
  end

  # ============================================================================
  # Write operations
  # ============================================================================

  @impl true
  def register(attrs, opts \\ []) when is_map(attrs) do
    span do
      set_attributes("db", operation: "insert", entity: "user")

      changeset_fn = Keyword.get(opts, :changeset_fn, &User.registration_changeset/2)

      %User{}
      |> changeset_fn.(attrs)
      |> Repo.insert()
    end
  end

  @impl true
  def append_intended_role(%User{} = user, role) when is_atom(role) do
    span do
      set_attributes("db", operation: "update", entity: "user")

      user
      |> User.add_role_changeset(role)
      |> Repo.update()
    end
  end

  @impl true
  def anonymize(%User{} = user) do
    span do
      set_attributes("db", operation: "update", entity: "user")

      Ecto.Multi.new()
      |> Ecto.Multi.update(:anonymize_user, User.anonymize_changeset(user))
      |> Ecto.Multi.delete_all(:delete_tokens, fn %{anonymize_user: anonymized_user} ->
        from(t in UserToken, where: t.user_id == ^anonymized_user.id)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{anonymize_user: user}} -> {:ok, user}
        {:error, :anonymize_user, changeset, _} -> {:error, changeset}
        {:error, _step, reason, _} -> {:error, reason}
      end
    end
  end

  @impl true
  def apply_email_change(%User{} = user, token) when is_binary(token) do
    span do
      set_attributes("db", operation: "update", entity: "user")

      context = "change:#{user.email}"

      Ecto.Multi.new()
      |> Ecto.Multi.run(:verify_token, fn _repo, _ ->
        # Trigger: token may be malformed (bad base64)
        # Why: verify_change_email_token_query returns bare :error for bad base64
        # Outcome: normalize to {:error, :invalid_token} instead of crashing
        case UserToken.verify_change_email_token_query(token, context) do
          {:ok, query} -> {:ok, query}
          :error -> {:error, :invalid_token}
        end
      end)
      |> Ecto.Multi.run(:fetch_token, fn repo, %{verify_token: query} ->
        case repo.one(query) do
          %UserToken{sent_to: email} = token_record -> {:ok, {token_record, email}}
          nil -> {:error, :token_not_found}
        end
      end)
      |> Ecto.Multi.run(:update_email, fn repo, %{fetch_token: {_token_record, email}} ->
        user
        |> User.email_changeset(%{email: email})
        |> repo.update()
      end)
      |> Ecto.Multi.delete_all(:delete_tokens, fn %{update_email: updated_user} ->
        from(UserToken, where: [user_id: ^updated_user.id, context: ^context])
      end)
      |> Repo.transaction()
      |> normalize_email_change_result()
    end
  end

  defp normalize_email_change_result({:ok, %{update_email: updated_user}}), do: {:ok, updated_user}

  defp normalize_email_change_result({:error, :verify_token, _reason, _}), do: {:error, :invalid_token}

  defp normalize_email_change_result({:error, :fetch_token, _reason, _}), do: {:error, :invalid_token}

  defp normalize_email_change_result({:error, :update_email, changeset, _}), do: {:error, changeset}

  defp normalize_email_change_result({:error, _step, reason, _}), do: {:error, reason}

  @impl true
  def resolve_magic_link(token) when is_binary(token) do
    span do
      set_attributes("db", operation: "select", entity: "user")

      # Trigger: token may be malformed (bad base64)
      # Why: verify_magic_link_token_query returns bare :error for bad base64
      # Outcome: normalize to {:error, :invalid_token} instead of crashing
      case UserToken.verify_magic_link_token_query(token) do
        {:ok, query} ->
          resolve_magic_link_query(Repo.one(query))

        :error ->
          {:error, :invalid_token}
      end
    end
  end

  # Trigger: unconfirmed user has a password set
  # Why: prevents session fixation attacks via magic link
  # Outcome: returns error instead of raising (use case decides how to handle)
  defp resolve_magic_link_query({%User{confirmed_at: nil, hashed_password: hash}, _token}) when not is_nil(hash) do
    {:error, :security_violation}
  end

  # Trigger: unconfirmed user without password (normal registration flow)
  # Why: first login confirms the email — use case handles confirmation
  # Outcome: returns {:unconfirmed, user} for use case to proceed
  defp resolve_magic_link_query({%User{confirmed_at: nil} = user, _token}) do
    {:ok, {:unconfirmed, user}}
  end

  # Trigger: confirmed user clicking magic link
  # Why: standard login — use case deletes the specific token
  # Outcome: returns {:confirmed, user, token} with the token to delete
  defp resolve_magic_link_query({user, token}) do
    {:ok, {:confirmed, user, token}}
  end

  defp resolve_magic_link_query(nil) do
    {:error, :not_found}
  end

  @impl true
  def confirm_and_cleanup_tokens(%User{} = user) do
    span do
      set_attributes("db", operation: "update", entity: "user")

      user
      |> User.confirm_changeset()
      |> TokenCleanup.update_user_and_delete_all_tokens()
    end
  end

  @impl true
  def delete_token(%UserToken{} = token) do
    span do
      set_attributes("db", operation: "delete", entity: "user")

      case Repo.delete(token) do
        {:ok, _} ->
          :ok

        # Trigger: constraint violation (e.g. foreign key)
        # Why: Repo.delete returns {:error, changeset} for constraint failures
        # Outcome: log for visibility but treat as success — token is invalidated either way
        {:error, changeset} ->
          Logger.warning("Token deletion failed: #{inspect(changeset)}")
          :ok
      end
    end
  rescue
    # Trigger: token already deleted by concurrent request
    # Why: Repo.delete raises StaleEntryError when the row is gone
    # Outcome: treat as success since the token is already gone
    Ecto.StaleEntryError -> :ok
  end
end
