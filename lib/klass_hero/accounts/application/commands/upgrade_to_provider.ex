defmodule KlassHero.Accounts.Application.Commands.UpgradeToProvider do
  @moduledoc """
  Use case for a staff member's deliberate self-upgrade to Provider (#968, ADR-0005).

  Provider-hood is always a person-initiated act — never automatic from being
  hired, never admin-initiated. This command is the only upgrade path: it creates
  a draft ProviderProfile for the EXISTING User (same identity) and appends
  `:provider` to `intended_roles`. Accounts may depend on Provider (but not vice
  versa), so this two-context orchestration belongs here, mirroring
  `LinkStaffInvitation`.

  The draft-birth policy (`:draft` status, `originated_from: :direct`, the
  person's name as placeholder business name) is owned by the Provider context
  via `Provider.create_draft_provider_profile/3`; the
  `/provider/complete-profile` flow collects real business details.

  Both writes run in one DB transaction (same Repo, different contexts), so a
  failure in either rolls back both — never a ProviderProfile whose user lacks
  `:provider`, nor the reverse. The unique index on `providers.identity_id` is
  the race backstop behind the existence pre-check.
  """

  alias KlassHero.Accounts.User
  alias KlassHero.Provider
  alias KlassHero.Repo

  @user_repository Application.compile_env!(:klass_hero, [:accounts, :for_storing_users])

  @doc """
  Creates a draft ProviderProfile for `user` and grants `:provider`, atomically.

  The `user` must come from the authenticated session — never from params.
  The user row is re-fetched inside the transaction so the role append and the
  profile's owner details build on current DB state, not the session's
  mount-time snapshot. Returns `{:error, :already_provider}` (no writes) when a
  profile already exists for this identity — including the race where another
  request creates it between the pre-check and the insert (unique-index
  backstop, normalized from `:duplicate_resource`).
  """
  @spec execute(User.t()) :: {:ok, User.t()} | {:error, :already_provider | term()}
  def execute(%User{} = user) do
    if Provider.has_provider_profile?(user.id) do
      {:error, :already_provider}
    else
      Repo.transaction(fn ->
        fresh_user = Repo.get!(User, user.id)

        with {:ok, _profile} <-
               Provider.create_draft_provider_profile(
                 fresh_user.id,
                 fresh_user.name,
                 fresh_user.email
               ),
             {:ok, updated_user} <- @user_repository.append_intended_role(fresh_user, :provider) do
          updated_user
        else
          {:error, :duplicate_resource} -> Repo.rollback(:already_provider)
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
  end
end
