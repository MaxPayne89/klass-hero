defmodule KlassHero.Shared.Domain.Models.PersistenceSupport do
  @moduledoc """
  Injects the standard `from_persistence/1` reconstruction helper into a domain
  model.

  `use KlassHero.Shared.Domain.Models.PersistenceSupport` defines:

      def from_persistence(attrs) when is_map(attrs) do
        {:ok, struct!(__MODULE__, attrs)}
      rescue
        ArgumentError -> {:error, :invalid_persistence_data}
      end

  This is the common case: rebuild a struct from already-validated persistence
  data, returning `{:error, :invalid_persistence_data}` when `@enforce_keys` are
  missing. The function is `defoverridable`, so models needing bespoke
  reconstruction (custom guards, error introspection) can define their own.
  """

  defmacro __using__(_opts) do
    quote do
      @doc """
      Reconstructs the struct from persistence data, skipping business validation.

      Returns `{:ok, struct}` or `{:error, :invalid_persistence_data}` when
      required keys are missing.
      """
      @spec from_persistence(map()) :: {:ok, struct()} | {:error, :invalid_persistence_data}
      def from_persistence(attrs) when is_map(attrs) do
        {:ok, struct!(__MODULE__, attrs)}
      rescue
        ArgumentError -> {:error, :invalid_persistence_data}
      end

      defoverridable from_persistence: 1
    end
  end
end
