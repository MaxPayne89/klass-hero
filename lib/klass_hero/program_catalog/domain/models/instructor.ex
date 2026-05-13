defmodule KlassHero.ProgramCatalog.Domain.Models.Instructor do
  @moduledoc """
  Value object representing an instructor assigned to a program.

  This is ProgramCatalog's own representation of who runs a program — an
  Anti-Corruption Layer (ACL) that prevents Provider's StaffMember from
  leaking into this bounded context.

  Populated at creation time from Provider data via the web layer.
  """

  @enforce_keys [:id, :name]

  defstruct [:id, :name, :headshot_url]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          headshot_url: String.t() | nil
        }

  @spec initials(t()) :: String.t()
  def initials(%__MODULE__{name: name}) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join("", fn token -> token |> String.first() |> String.upcase() end)
  end

  @spec new(map()) :: {:ok, t()} | {:error, [String.t()]}
  def new(attrs) when is_map(attrs) do
    attrs_with_defaults = Map.put_new(attrs, :headshot_url, nil)

    case validate(attrs_with_defaults) do
      [] -> {:ok, struct!(__MODULE__, attrs_with_defaults)}
      errors -> {:error, errors}
    end
  end

  @spec from_persistence(map()) :: {:ok, t()} | {:error, :invalid_persistence_data}
  def from_persistence(%{id: id, name: name} = attrs) when is_binary(id) and is_binary(name) do
    {:ok, struct!(__MODULE__, Map.put_new(attrs, :headshot_url, nil))}
  end

  def from_persistence(_), do: {:error, :invalid_persistence_data}

  defp validate(attrs) do
    []
    |> validate_id(attrs[:id])
    |> validate_name(attrs[:name])
  end

  defp validate_id(errors, id) when is_binary(id) and byte_size(id) > 0 do
    # Trigger: id is a non-empty binary
    # Why: still need to check for whitespace-only strings
    # Outcome: error added if trimmed string is empty
    if String.trim(id) == "", do: ["ID cannot be empty" | errors], else: errors
  end

  defp validate_id(errors, _), do: ["ID cannot be empty" | errors]

  defp validate_name(errors, name) when is_binary(name) and byte_size(name) > 0 do
    if String.trim(name) == "", do: ["Name cannot be empty" | errors], else: errors
  end

  defp validate_name(errors, _), do: ["Name cannot be empty" | errors]
end
