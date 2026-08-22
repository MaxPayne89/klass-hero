defmodule KlassHero.Provider.StepKey do
  @moduledoc """
  Custom Ecto type for a `VerificationStep`'s `key` (and the atoms in `requires`).

  Step keys are a closed set of atoms defined in the `KlassHero.Provider.Vetting`
  track catalog (compiled into the app), so they always exist. This type keeps the
  in-memory struct carrying atoms — matching the functional core — while persisting
  strings. Used both as `field :key, StepKey` and `field :requires, {:array, StepKey}`.

  On load, an unknown value (a key removed from the catalog) yields `:error` rather
  than silently minting an atom; the closed-set guarantee means this should not occur
  for live data.
  """

  use Ecto.Type

  @impl true
  def type, do: :string

  @impl true
  def cast(value) when is_atom(value) and not is_nil(value), do: {:ok, value}
  def cast(value) when is_binary(value), do: load(value)
  def cast(_), do: :error

  @impl true
  def load(value) when is_binary(value) do
    {:ok, String.to_existing_atom(value)}
  rescue
    ArgumentError -> :error
  end

  def load(_), do: :error

  @impl true
  def dump(value) when is_atom(value) and not is_nil(value), do: {:ok, Atom.to_string(value)}
  def dump(value) when is_binary(value), do: {:ok, value}
  def dump(_), do: :error
end
