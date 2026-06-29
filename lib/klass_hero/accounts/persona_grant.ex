defmodule KlassHero.Accounts.PersonaGrant do
  @moduledoc """
  Shared transaction shape for persona-granting flows (ADR-0005).

  Every flow where a user gains a persona — provider upgrade (#968), staff
  invitation link (#967), self-staffing (#969) — performs the same two-step
  write: a cross-context persona write plus an `intended_roles` append, both
  atomic, both built on a user row re-fetched INSIDE the transaction so a
  mount-stale session struct can never clobber concurrently granted roles
  (the lost-update class fixed in the #968 review).

  Internal to Accounts: the context's persona functions call `grant/3`;
  everything context-specific (guards, error vocabulary normalization) stays in
  the calling function.
  """

  alias KlassHero.Accounts.User
  alias KlassHero.Repo

  @doc """
  Runs `cross_context_write.(fresh_user)` and appends `role`, atomically.

  Returns `{:ok, {updated_user, write_result}}`; any `{:error, reason}` from
  either step rolls back both and is returned verbatim.
  """
  @spec grant(User.t(), atom(), (User.t() -> {:ok, term()} | {:error, term()})) ::
          {:ok, {User.t(), term()}} | {:error, term()}
  def grant(%User{} = user, role, cross_context_write) when is_atom(role) and is_function(cross_context_write, 1) do
    Repo.transaction(fn ->
      fresh_user = Repo.get!(User, user.id)

      with {:ok, granted} <- cross_context_write.(fresh_user),
           {:ok, updated_user} <- fresh_user |> User.add_role_changeset(role) |> Repo.update() do
        {updated_user, granted}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end
end
