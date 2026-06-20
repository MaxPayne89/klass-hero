defmodule KlassHero.Provider.Adapters.Driving.Events.EventHandlers.VettingVerificationSync do
  @moduledoc """
  Shared bridge from a fully/partly verified `VettingCase` to the published `ProviderProfile.verified`
  fact, used by both vetting step handlers (`AdvanceVettingStepOnDocumentReview` and
  `AdvanceVettingStepOnIdentityOutcome`).

  `admin_id` is the human reviewer for document-driven changes, or `nil` for system-driven
  (Stripe Identity) changes.
  """

  alias KlassHero.Provider.Application.Commands.Providers.UnverifyProvider
  alias KlassHero.Provider.Application.Commands.Providers.VerifyProvider

  require Logger

  @profile_query Application.compile_env!(:klass_hero, [:provider, :for_querying_provider_profiles])

  @doc "Verifies the provider, logging (not raising) if the command fails."
  @spec verify(String.t(), String.t() | nil) :: :ok
  def verify(provider_id, admin_id) do
    case VerifyProvider.execute(%{provider_id: provider_id, admin_id: admin_id}) do
      {:ok, _} -> :ok
      {:error, reason} -> Logger.warning("Auto-verify failed for provider #{provider_id}: #{inspect(reason)}")
    end
  end

  @doc "Unverifies the provider only if currently verified, logging (not raising) if the command fails."
  @spec maybe_unverify(String.t(), String.t() | nil) :: :ok
  def maybe_unverify(provider_id, admin_id) do
    with {:ok, profile} <- @profile_query.get(provider_id),
         true <- profile.verified do
      case UnverifyProvider.execute(%{provider_id: provider_id, admin_id: admin_id}) do
        {:ok, _} -> :ok
        {:error, reason} -> Logger.warning("Auto-unverify failed for provider #{provider_id}: #{inspect(reason)}")
      end
    else
      _ -> :ok
    end
  end
end
