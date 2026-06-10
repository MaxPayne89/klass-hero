defmodule KlassHero.Accounts.Application.Commands.AddSelfAsStaff do
  @moduledoc """
  Use case for a provider deliberately staffing themselves (#969, ADR-0005).

  The mirror of `UpgradeToProvider`: the StaffMember row lives in Provider, the
  `:staff` role lives in Accounts, and Accounts may depend on Provider (not vice
  versa), so the orchestration belongs here.

  The own business is resolved from the user's identity — never from caller
  params — so a provider can only ever self-staff their own team. The staff-row
  birth policy (pre-linked, `:accepted`, no token, no invitation event) is owned
  by `Provider.create_self_staff_member/3`.

  Both writes run in one DB transaction with the user re-fetched inside it, so
  the role append builds on current DB state rather than the session's
  mount-time snapshot.
  """

  alias KlassHero.Accounts.User
  alias KlassHero.Provider
  alias KlassHero.Repo

  @user_repository Application.compile_env!(:klass_hero, [:accounts, :for_storing_users])

  @doc """
  Creates the user's own staff row and grants `:staff`, atomically.

  The `user` must come from the authenticated session — never from params.
  Returns `{:error, :not_a_provider}` when the user has no provider profile,
  `{:error, :already_staffed}` when an active self row already exists.
  """
  @spec execute(User.t(), map()) ::
          {:ok, User.t()} | {:error, :not_a_provider | :already_staffed | term()}
  def execute(%User{} = user, staff_attrs) when is_map(staff_attrs) do
    case Provider.get_provider_by_identity(user.id) do
      {:ok, provider} -> self_staff(provider, user, staff_attrs)
      {:error, :not_found} -> {:error, :not_a_provider}
    end
  end

  defp self_staff(provider, user, staff_attrs) do
    Repo.transaction(fn ->
      fresh_user = Repo.get!(User, user.id)

      with {:ok, _staff} <-
             Provider.create_self_staff_member(provider.id, fresh_user.id, staff_attrs),
           {:ok, updated_user} <- @user_repository.append_intended_role(fresh_user, :staff) do
        updated_user
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end
end
