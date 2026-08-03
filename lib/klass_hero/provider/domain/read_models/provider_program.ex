defmodule KlassHero.Provider.Domain.ReadModels.ProviderProgram do
  @moduledoc """
  Read-model projection of a program owned by a provider.

  Populated by the `ProviderPrograms` projection GenServer. Display-optimized;
  contains no business logic. Use the query port to fetch instances.
  """

  @typedoc "A denormalized provider program record for display in the provider dashboard."
  @type t :: %__MODULE__{
          program_id: String.t(),
          provider_id: String.t(),
          name: String.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @enforce_keys [:program_id, :provider_id, :name]

  defstruct [
    :program_id,
    :provider_id,
    :name,
    :inserted_at,
    :updated_at
  ]
end
