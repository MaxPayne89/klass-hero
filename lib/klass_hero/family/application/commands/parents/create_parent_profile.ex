defmodule KlassHero.Family.Application.Commands.Parents.CreateParentProfile do
  @moduledoc """
  Use case for creating a new parent profile.

  Orchestrates domain validation and persistence through the repository port.
  """

  alias KlassHero.Family.Domain.Models.ParentProfile
  alias KlassHero.Shared.CommandResult

  @repository Application.compile_env!(:klass_hero, [:family, :for_storing_parent_profiles])

  @doc """
  Creates a new parent profile for the given identity.

  Returns:
  - `{:ok, ParentProfile.t()}` on success
  - `{:error, {:validation_error, errors}}` for domain validation failures
  - `{:error, :duplicate_resource}` if profile already exists
  - `{:error, changeset}` for persistence validation failures
  """
  def execute(attrs) when is_map(attrs) do
    attrs_with_id = Map.put_new(attrs, :id, Ecto.UUID.generate())

    with {:ok, _validated} <- ParentProfile.new(attrs_with_id),
         {:ok, persisted} <- @repository.create_parent_profile(attrs_with_id) do
      {:ok, persisted}
    else
      result -> CommandResult.wrap_validation_errors(result)
    end
  end
end
