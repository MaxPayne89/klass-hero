defmodule KlassHero.Shared.ForManagingFeatureFlags do
  @moduledoc """
  Port for feature flag operations.

  Supports global boolean gates and per-actor gates:
  - `enabled?/2` — checks if a flag is globally enabled
  - `enabled?/3` — checks if a flag is enabled for a specific actor
  - `enable/2` — globally enables a flag
  - `disable/2` — globally disables a flag
  """

  @type flag_name :: atom()
  @type actor :: struct()
  @type error_reason :: :persistence_error | term()

  @doc "Check if a flag is globally enabled."
  @callback enabled?(flag_name(), keyword()) :: {:ok, boolean()} | {:error, error_reason()}

  @doc "Check if a flag is enabled for a specific actor."
  @callback enabled?(flag_name(), actor(), keyword()) ::
              {:ok, boolean()} | {:error, error_reason()}

  @doc "Globally enable a flag."
  @callback enable(flag_name(), keyword()) :: :ok | {:error, error_reason()}

  @doc "Globally disable a flag."
  @callback disable(flag_name(), keyword()) :: :ok | {:error, error_reason()}
end
