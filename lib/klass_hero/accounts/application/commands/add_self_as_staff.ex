defmodule KlassHero.Accounts.Application.Commands.AddSelfAsStaff do
  @moduledoc """
  Use case for a provider deliberately staffing themselves (#969, ADR-0005).

  The mirror of `UpgradeToProvider`: the StaffMember row lives in Provider, the
  `:staff` role lives in Accounts, and Accounts may depend on Provider (not vice
  versa), so the orchestration belongs here.

  The own business is resolved from the user's identity — never from caller
  params — so a provider can only ever self-staff their own team. The staff-row
  birth policy (pre-linked, `:accepted`, no token, no invitation event) is owned
  by `Provider.create_self_staff_member/3`. The row's email is forced to the
  account email inside the transaction: a linked self row never carries an
  address its `user_id` doesn't own, whatever the form submitted.

  Transaction/re-fetch semantics live in `PersonaGrant`.
  """

  alias KlassHero.Accounts.Application.Commands.PersonaGrant
  alias KlassHero.Accounts.User
  alias KlassHero.Provider
  alias KlassHero.Provider.Domain.Models.StaffMember

  @doc """
  Creates the user's own staff row and grants `:staff`, atomically.

  `staff_attrs` accepts the staff-form fields (`:first_name`, `:last_name`,
  `:role`, `:bio`, `:tags`, `:qualifications`, `:headshot_url`, `:pay_rate`);
  `:email` is overridden with the account email, linkage fields are owned by
  the Provider command. The `user` must come from the authenticated session —
  never from params.

  Returns `{:ok, updated_user, staff}`, `{:error, :not_a_provider}` when the
  user has no provider profile, or `{:error, :already_staffed}` when an active
  self row already exists.
  """
  @spec execute(User.t(), map()) ::
          {:ok, User.t(), StaffMember.t()}
          | {:error, :not_a_provider | :already_staffed | term()}
  def execute(%User{} = user, staff_attrs) when is_map(staff_attrs) do
    case Provider.get_provider_by_identity(user.id) do
      {:ok, provider} -> self_staff(provider, user, staff_attrs)
      {:error, :not_found} -> {:error, :not_a_provider}
    end
  end

  defp self_staff(provider, user, staff_attrs) do
    grant_result =
      PersonaGrant.grant(user, :staff, fn fresh_user ->
        attrs = Map.put(staff_attrs, :email, fresh_user.email)
        Provider.create_self_staff_member(provider.id, fresh_user.id, attrs)
      end)

    with {:ok, {updated_user, staff}} <- grant_result do
      {:ok, updated_user, staff}
    end
  end
end
