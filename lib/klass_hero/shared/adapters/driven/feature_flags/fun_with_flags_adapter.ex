defmodule KlassHero.Shared.Adapters.Driven.FeatureFlags.FunWithFlagsAdapter do
  @moduledoc """
  Production feature flag adapter backed by `fun_with_flags`.

  Delegates to `FunWithFlags` and normalizes return values to match
  the `ForManagingFeatureFlags` port contract.
  """

  @behaviour KlassHero.Shared.ForManagingFeatureFlags

  @impl true
  def enabled?(flag_name, _opts) do
    {:ok, FunWithFlags.enabled?(flag_name)}
  end

  @impl true
  def enabled?(flag_name, actor, _opts) do
    {:ok, FunWithFlags.enabled?(flag_name, for: actor)}
  end

  @impl true
  def enable(flag_name, _opts) do
    case FunWithFlags.enable(flag_name) do
      {:ok, _flag} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def disable(flag_name, _opts) do
    case FunWithFlags.disable(flag_name) do
      {:ok, _flag} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
