defmodule KlassHero.Provider.Application.Commands.Providers.VerifyProvider do
  @moduledoc """
  Use case for admin verifying a provider.

  Orchestrates the provider verification workflow:
  1. Retrieves the provider profile from the repository
  2. Sets verified: true and verified_at timestamp
  3. Persists the updated profile
  4. Publishes an integration event for cross-context notification

  This use case is idempotent - verifying an already verified provider succeeds
  and updates the verified_at timestamp.
  """

  alias KlassHero.Provider.Domain.Events.ProviderEvents
  alias KlassHero.Provider.Domain.Models.ProviderProfile
  alias KlassHero.Shared.IntegrationEventPublishing

  @query Application.compile_env!(:klass_hero, [:provider, :for_querying_provider_profiles])
  @repository Application.compile_env!(:klass_hero, [:provider, :for_storing_provider_profiles])

  @doc """
  Verifies a provider profile.

  ## Parameters

  - `provider_id` - ID of the provider profile to verify
  - `admin_id` - ID of the admin performing the verification (for audit)

  ## Returns

  - `{:ok, ProviderProfile.t()}` on success with verified=true
  - `{:error, :not_found}` if provider profile doesn't exist
  """
  def execute(%{provider_id: provider_id, admin_id: admin_id}) do
    with {:ok, profile} <- @query.get(provider_id),
         {:ok, verified} <- ProviderProfile.verify(profile, admin_id),
         {:ok, persisted} <- @repository.update(verified),
         :ok <- publish_event(persisted, admin_id) do
      {:ok, persisted}
    end
  end

  defp publish_event(profile, admin_id) do
    profile
    |> ProviderEvents.provider_verified(admin_id)
    |> IntegrationEventPublishing.publish()
  end
end
