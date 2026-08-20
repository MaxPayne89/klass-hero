defmodule KlassHero.Accounts.UserRole do
  @moduledoc """
  Valid user roles. Roles: `:parent`, `:provider`, `:staff`
  (ADR-0005: staff is an independent persona, not a kind of provider).
  """

  @valid_roles [:parent, :provider, :staff]

  @type t :: :parent | :provider | :staff

  @doc "Returns all valid roles."
  @spec valid_roles() :: [t()]
  def valid_roles, do: @valid_roles

  @doc "Returns true if the given role atom is valid."
  @spec valid_role?(term()) :: boolean()
  def valid_role?(role) when is_atom(role), do: role in @valid_roles
  def valid_role?(_), do: false

  @doc "Converts a role atom to its string representation."
  @spec to_string(term()) :: {:ok, String.t()} | {:error, :invalid_role}
  def to_string(role) when role in @valid_roles do
    {:ok, Atom.to_string(role)}
  end

  def to_string(_), do: {:error, :invalid_role}

  @doc "Converts a string to a role atom. Uses `String.to_existing_atom/1` to avoid atom table pollution."
  @spec from_string(term()) :: {:ok, t()} | {:error, :invalid_role}
  def from_string(str) when is_binary(str) do
    role = String.to_existing_atom(str)
    if role in @valid_roles, do: {:ok, role}, else: {:error, :invalid_role}
  rescue
    ArgumentError -> {:error, :invalid_role}
  end

  def from_string(_), do: {:error, :invalid_role}
end
