defmodule KlassHero.Shared.FeatureFlags do
  @moduledoc """
  Public API for feature flag operations.

  Delegates to the configured adapter (FunWithFlags in prod, Stub in tests).

  ## Usage

      # Check if a flag is enabled
      {:ok, enabled?} = FeatureFlags.enabled?(:new_booking_flow)

      # Check with actor-specific gating
      {:ok, enabled?} = FeatureFlags.enabled?(:beta_feature, current_user)

      # Enable/disable a flag
      :ok = FeatureFlags.enable(:new_booking_flow)
      :ok = FeatureFlags.disable(:new_booking_flow)
  """

  alias KlassHero.Shared.ForManagingFeatureFlags

  @doc "Check if a flag is globally enabled."
  @spec enabled?(ForManagingFeatureFlags.flag_name(), keyword()) ::
          {:ok, boolean()} | {:error, term()}
  def enabled?(flag_name, opts \\ []) do
    adapter(opts).enabled?(flag_name, opts)
  end

  @doc "Check if a flag is enabled for a specific actor."
  @spec enabled?(ForManagingFeatureFlags.flag_name(), struct(), keyword()) ::
          {:ok, boolean()} | {:error, term()}
  def enabled?(flag_name, actor, opts) do
    adapter(opts).enabled?(flag_name, actor, opts)
  end

  @doc "Globally enable a flag."
  @spec enable(ForManagingFeatureFlags.flag_name(), keyword()) :: :ok | {:error, term()}
  def enable(flag_name, opts \\ []) do
    adapter(opts).enable(flag_name, opts)
  end

  @doc "Globally disable a flag."
  @spec disable(ForManagingFeatureFlags.flag_name(), keyword()) :: :ok | {:error, term()}
  def disable(flag_name, opts \\ []) do
    adapter(opts).disable(flag_name, opts)
  end

  defp adapter(opts) do
    Keyword.get_lazy(opts, :adapter, fn ->
      Application.get_env(:klass_hero, :feature_flags)[:adapter]
    end)
  end
end
