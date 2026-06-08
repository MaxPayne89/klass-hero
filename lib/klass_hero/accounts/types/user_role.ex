defmodule KlassHero.Accounts.Types.UserRole do
  @moduledoc """
  Domain model for user roles with permission structure.

  This module defines valid user roles and their associated permissions.
  It provides conversion utilities between atoms (Elixir representation)
  and strings (database/form representation).

  ## Valid Roles

  - `:parent` - Users who enroll children in programs
  - `:provider` - Users who offer programs and services
  - `:staff` - Staff members working for a provider (ADR-0005: an independent
    persona, not a kind of provider)

  ## Permissions

  Permission structure is defined for future authorization features.
  No enforcement logic is implemented at this time - this is purely
  a structural definition for future use.

  ## Examples

      iex> UserRole.valid_role?(:parent)
      true

      iex> UserRole.to_string(:parent)
      {:ok, "parent"}

      iex> UserRole.from_string("parent")
      {:ok, :parent}

      iex> UserRole.permissions(:parent)
      [:view_programs, :enroll_children, :view_child_progress,
       :manage_family_profile, :submit_reviews]
  """

  @valid_roles [:parent, :provider, :staff]

  # Permission structure for future authorization (not enforced yet)
  @role_permissions %{
    parent: [
      :view_programs,
      :enroll_children,
      :view_child_progress,
      :manage_family_profile,
      :submit_reviews
    ],
    provider: [
      :manage_programs,
      :view_enrollments,
      :manage_schedule,
      :view_analytics,
      :respond_to_reviews
    ],
    staff: [
      :view_assigned_programs,
      :view_staff_dashboard,
      :manage_own_profile
    ]
  }

  @type t :: :parent | :provider | :staff

  @doc """
  Returns the list of all valid roles.

  ## Examples

      iex> UserRole.valid_roles()
      [:parent, :provider]
  """
  @spec valid_roles() :: [t()]
  def valid_roles, do: @valid_roles

  @doc """
  Checks if the given role is valid.

  ## Examples

      iex> UserRole.valid_role?(:parent)
      true

      iex> UserRole.valid_role?(:admin)
      false

      iex> UserRole.valid_role?("parent")
      false
  """
  @spec valid_role?(term()) :: boolean()
  def valid_role?(role) when is_atom(role), do: role in @valid_roles
  def valid_role?(_), do: false

  @doc """
  Converts a role atom to a string.

  ## Examples

      iex> UserRole.to_string(:parent)
      {:ok, "parent"}

      iex> UserRole.to_string(:invalid)
      {:error, :invalid_role}
  """
  @spec to_string(term()) :: {:ok, String.t()} | {:error, :invalid_role}
  def to_string(role) when role in @valid_roles do
    {:ok, Atom.to_string(role)}
  end

  def to_string(_), do: {:error, :invalid_role}

  @doc """
  Converts a string to a role atom.

  Uses `String.to_existing_atom/1` to prevent atom table pollution.
  Only converts strings that match valid role names.

  ## Examples

      iex> UserRole.from_string("parent")
      {:ok, :parent}

      iex> UserRole.from_string("invalid")
      {:error, :invalid_role}
  """
  @spec from_string(term()) :: {:ok, t()} | {:error, :invalid_role}
  def from_string(str) when is_binary(str) do
    role = String.to_existing_atom(str)
    if role in @valid_roles, do: {:ok, role}, else: {:error, :invalid_role}
  rescue
    ArgumentError -> {:error, :invalid_role}
  end

  def from_string(_), do: {:error, :invalid_role}

  @doc """
  Returns the list of permissions associated with a role.

  **Note:** This is a structural definition for future authorization.
  No permission enforcement is currently implemented.

  ## Examples

      iex> UserRole.permissions(:parent)
      [:view_programs, :enroll_children, :view_child_progress,
       :manage_family_profile, :submit_reviews]

      iex> UserRole.permissions(:provider)
      [:manage_programs, :view_enrollments, :manage_schedule,
       :view_analytics, :respond_to_reviews]

      iex> UserRole.permissions(:invalid)
      []
  """
  @spec permissions(term()) :: [atom()]
  def permissions(role) when is_atom(role) do
    Map.get(@role_permissions, role, [])
  end

  def permissions(_), do: []
end
