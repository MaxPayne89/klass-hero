defmodule KlassHero.Family.Application.Commands.Children.UpdateChild do
  @moduledoc """
  Use case for updating an existing child.

  Loads the child, validates updated fields at the domain level,
  then persists via the repository port.
  """

  alias KlassHero.Family.Domain.Events.FamilyEvents
  alias KlassHero.Family.Domain.Models.Child
  alias KlassHero.Shared.CommandResult
  alias KlassHero.Shared.EventDispatchHelper

  @context KlassHero.Family
  @repository Application.compile_env!(:klass_hero, [:family, :for_storing_children])

  @doc """
  Updates an existing child with the given attributes.

  Returns:
  - `{:ok, Child.t()}` on success
  - `{:error, :not_found}` if child doesn't exist
  - `{:error, {:validation_error, errors}}` for domain validation failures
  - `{:error, changeset}` for persistence validation failures
  """
  def execute(child_id, attrs) when is_binary(child_id) and is_map(attrs) do
    with {:ok, existing} <- @repository.get_by_id(child_id),
         merged = Map.merge(Map.from_struct(existing), attrs),
         {:ok, _validated} <- Child.new(merged),
         {:ok, updated} <- @repository.update(child_id, attrs) do
      dispatch_child_updated(updated)
      {:ok, updated}
    else
      result -> CommandResult.wrap_validation_errors(result)
    end
  end

  defp dispatch_child_updated(child) do
    # Downstream contexts (e.g. Messaging) refresh local child name lookups; parent_id not on child struct.
    FamilyEvents.child_updated(child.id, %{
      child_id: child.id,
      first_name: child.first_name,
      last_name: child.last_name
    })
    |> EventDispatchHelper.dispatch(@context)
  end
end
