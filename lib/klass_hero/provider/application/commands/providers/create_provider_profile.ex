defmodule KlassHero.Provider.Application.Commands.Providers.CreateProviderProfile do
  @moduledoc """
  Use case for creating a new provider profile.

  Orchestrates domain validation and persistence through the repository port.
  """

  alias KlassHero.Provider.Domain.Models.ProviderProfile
  alias KlassHero.Provider.Domain.Models.VettingCase
  alias KlassHero.Repo
  alias KlassHero.Shared.CommandResult

  @repository Application.compile_env!(:klass_hero, [:provider, :for_storing_provider_profiles])
  @vetting_repository Application.compile_env!(:klass_hero, [:provider, :for_storing_vetting_cases])

  @doc """
  Creates a new provider profile for the given identity.

  Returns:
  - `{:ok, ProviderProfile.t()}` on success
  - `{:error, {:validation_error, errors}}` for domain validation failures
  - `{:error, :duplicate_resource}` if profile already exists
  - `{:error, changeset}` for persistence validation failures
  """
  def execute(attrs) when is_map(attrs) do
    attrs_with_id = Map.put_new(attrs, :id, Ecto.UUID.generate())

    case ProviderProfile.new(attrs_with_id) do
      {:ok, _validated} ->
        # Profile and its Vetting Case are seeded together — a provider must never exist without
        # a case to be vetted through (same DB → one transaction, not an integration event).
        Repo.transaction(fn ->
          with {:ok, persisted} <- @repository.create_provider_profile(attrs_with_id),
               {:ok, _case} <- seed_vetting_case(persisted) do
            persisted
          else
            {:error, reason} -> Repo.rollback(reason)
          end
        end)
        |> CommandResult.wrap_validation_errors()

      result ->
        CommandResult.wrap_validation_errors(result)
    end
  end

  defp seed_vetting_case(profile) do
    profile.id
    |> VettingCase.new_for_track(profile.entity_type)
    |> @vetting_repository.create()
  end
end
