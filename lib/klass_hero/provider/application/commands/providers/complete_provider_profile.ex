defmodule KlassHero.Provider.Application.Commands.Providers.CompleteProviderProfile do
  @moduledoc """
  Use case for completing a draft provider profile.

  When a staff member opts into the provider role during activation,
  StaffInvitationStatusHandler creates a minimal profile with profile_status: :draft.
  This command accepts the full set of completion fields, validates at the domain
  level, then persists the completed profile with profile_status: :active.

  Only profiles with profile_status: :draft can be completed.
  """

  alias KlassHero.Provider.Domain.Models.ProviderProfile
  alias KlassHero.Shared.CommandResult

  @query Application.compile_env!(:klass_hero, [:provider, :for_querying_provider_profiles])
  @repository Application.compile_env!(:klass_hero, [:provider, :for_storing_provider_profiles])

  @doc """
  Completes a draft provider profile.

  Returns:
  - `{:ok, ProviderProfile.t()}` on success (profile_status now :active)
  - `{:error, :not_found}` if provider doesn't exist
  - `{:error, :already_active}` if profile is not in draft status
  - `{:error, {:validation_error, errors}}` for domain validation failures
  - `{:error, changeset}` for persistence validation failures
  """
  def execute(provider_id, attrs) when is_binary(provider_id) and is_map(attrs) do
    with {:ok, existing} <- @query.get(provider_id),
         {:ok, completed} <- ProviderProfile.complete_profile(existing, attrs),
         {:ok, persisted} <- @repository.update(completed) do
      {:ok, persisted}
    else
      result -> CommandResult.wrap_validation_errors(result)
    end
  end
end
