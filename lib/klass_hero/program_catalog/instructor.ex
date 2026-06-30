defmodule KlassHero.ProgramCatalog.Instructor do
  @moduledoc """
  Value object representing an instructor assigned to a program.

  Program Catalog's own representation of who runs a program — an
  Anti-Corruption Layer that keeps Provider's `StaffMember` from leaking into
  this context. Instructor data is denormalized into flat columns on the
  `programs` table; this struct is assembled from those columns by the context
  loader and exposed as `program.instructor`.
  """

  alias KlassHero.Shared.NameUtils

  @enforce_keys [:id, :name]

  defstruct [:id, :name, :headshot_url]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          headshot_url: String.t() | nil
        }

  @doc "The instructor's initials, derived from their name."
  @spec initials(t()) :: String.t()
  def initials(%__MODULE__{name: name}), do: NameUtils.initials_from_name(name)

  @doc """
  Builds an instructor from trusted persistence data (flat program columns).

  Returns `{:error, :invalid_persistence_data}` when the id/name are missing or
  not strings, letting the caller decide how to degrade.
  """
  @spec from_persistence(map()) :: {:ok, t()} | {:error, :invalid_persistence_data}
  def from_persistence(%{id: id, name: name} = attrs) when is_binary(id) and is_binary(name) do
    {:ok, struct!(__MODULE__, Map.put_new(attrs, :headshot_url, nil))}
  end

  def from_persistence(_), do: {:error, :invalid_persistence_data}
end
