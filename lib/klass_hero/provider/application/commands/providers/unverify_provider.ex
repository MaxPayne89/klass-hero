defmodule KlassHero.Provider.Application.Commands.Providers.UnverifyProvider do
  @moduledoc """
  Use case for admin revoking provider verification.

  Orchestrates the provider unverification workflow:
  1. Retrieves the provider profile from the repository
  2. Sets verified: false and clears verified_at timestamp
  3. Persists the updated profile
  4. Publishes an integration event for cross-context notification

  This use case is idempotent - unverifying an already unverified provider succeeds.
  """

  alias KlassHero.Provider.Domain.Events.ProviderEvents
  alias KlassHero.Provider.Domain.Models.ProviderProfile
  alias KlassHero.Shared.IntegrationEventPublishing

  @query Application.compile_env!(:klass_hero, [:provider, :for_querying_provider_profiles])
  @repository Application.compile_env!(:klass_hero, [:provider, :for_storing_provider_profiles])

  @doc """
  Revokes verification from a provider profile.

  ## Parameters

  - `provider_id` - ID of the provider profile to unverify
  - `admin_id` - ID of the admin performing the unverification (for audit)

  ## Returns

  - `{:ok, ProviderProfile.t()}` on success with verified=false
  - `{:error, :not_found}` if provider profile doesn't exist
  """
  def execute(%{provider_id: provider_id, admin_id: admin_id}) do
    with {:ok, profile} <- @query.get(provider_id),
         {:ok, unverified} <- ProviderProfile.unverify(profile),
         {:ok, persisted} <- @repository.update(unverified),
         :ok <- publish_event(persisted, admin_id) do
      {:ok, persisted}
    end
  end

  defp publish_event(profile, admin_id) do
    profile
    |> ProviderEvents.provider_unverified(admin_id)
    |> IntegrationEventPublishing.publish()
  end
end
