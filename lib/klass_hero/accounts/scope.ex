defmodule KlassHero.Accounts.Scope do
  @moduledoc """
  Caller scope propagated through public interfaces. Carries the authenticated user,
  resolved roles, and profile structs. Extend fields as application requirements grow.
  """

  alias KlassHero.Accounts.User
  alias KlassHero.Family
  alias KlassHero.Provider

  defstruct user: nil,
            roles: [],
            parent: nil,
            provider: nil,
            staff_member: nil

  @doc "Creates a scope for the given user, or nil if none."
  def for_user(%User{} = user) do
    %__MODULE__{user: user}
  end

  def for_user(nil), do: nil

  @doc """
  Resolves roles by checking profile existence. Updates `roles`, `parent`, `provider`,
  and `staff_member` on the scope.
  """
  def resolve_roles(%__MODULE__{user: nil} = scope), do: scope

  def resolve_roles(%__MODULE__{user: user} = scope) do
    parent = extract_profile(Family.get_parent_by_identity(user.id))
    provider = extract_profile(Provider.get_provider_by_identity(user.id))

    # Skip staff DB query for 99%+ of users who never registered as staff
    staff_member =
      if :staff in (user.intended_roles || []),
        do: extract_profile(Provider.get_active_staff_member_by_user(user.id))

    roles =
      []
      |> maybe_add_role(parent, :parent)
      |> maybe_add_role(provider, :provider)
      |> maybe_add_role(staff_member, :staff)

    %{scope | roles: roles, parent: parent, provider: provider, staff_member: staff_member}
  end

  @doc "Returns true if the scope has the given role."
  def has_role?(%__MODULE__{roles: roles}, role) when is_atom(role) do
    role in roles
  end

  @doc "Returns true if the scope has a parent profile."
  def parent?(%__MODULE__{parent: parent}), do: parent != nil

  @doc "Returns true if the scope has a provider profile."
  def provider?(%__MODULE__{provider: provider}), do: provider != nil

  @doc """
  Returns true if the scope has a staff membership (a Staff Member record).
  """
  def staff?(%__MODULE__{staff_member: staff_member}), do: staff_member != nil

  @doc """
  Returns true if the scope holds both a provider and a staff persona.
  """
  def dual_role?(%__MODULE__{} = scope), do: provider?(scope) and staff?(scope)

  @doc "Returns the parent's subscription tier, or nil if no parent profile."
  def parent_tier(%__MODULE__{parent: nil}), do: nil
  def parent_tier(%__MODULE__{parent: %{subscription_tier: tier}}), do: tier

  defp extract_profile({:ok, profile}), do: profile
  defp extract_profile({:error, _}), do: nil

  defp maybe_add_role(roles, nil, _role), do: roles
  defp maybe_add_role(roles, _profile, role), do: [role | roles]
end
