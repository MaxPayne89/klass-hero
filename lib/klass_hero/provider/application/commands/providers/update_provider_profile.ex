defmodule KlassHero.Provider.Application.Commands.Providers.UpdateProviderProfile do
  @moduledoc """
  Use case for updating an existing provider profile.

  Loads the provider, merges updated fields into the domain struct,
  validates at the domain level, then persists via the repository port.
  """

  alias KlassHero.Provider.Domain.Models.ProviderProfile
  alias KlassHero.Shared.CommandResult

  @query Application.compile_env!(:klass_hero, [:provider, :for_querying_provider_profiles])
  @repository Application.compile_env!(:klass_hero, [:provider, :for_storing_provider_profiles])

  @allowed_fields ~w(description logo_url)a

  @doc """
  Updates an existing provider profile with the given attributes.

  Only the fields in `@allowed_fields` are accepted; all other keys are stripped.

  Returns:
  - `{:ok, ProviderProfile.t()}` on success
  - `{:error, :not_found}` if provider doesn't exist
  - `{:error, {:validation_error, errors}}` for domain validation failures
  - `{:error, changeset}` for persistence validation failures
  """
  def execute(provider_id, attrs) when is_binary(provider_id) and is_map(attrs) do
    attrs = Map.take(attrs, @allowed_fields)

    with {:ok, existing} <- @query.get(provider_id),
         merged = Map.merge(Map.from_struct(existing), attrs),
         {:ok, _validated} <- ProviderProfile.new(merged),
         # Trigger: domain validation passed, now persist
         # Why: we update the existing struct (not the validated one) with new attrs
         #      to preserve fields that ProviderProfile.new/1 might reset (timestamps)
         updated = struct(existing, attrs),
         {:ok, persisted} <- @repository.update(updated) do
      {:ok, persisted}
    else
      result -> CommandResult.wrap_validation_errors(result)
    end
  end
end
