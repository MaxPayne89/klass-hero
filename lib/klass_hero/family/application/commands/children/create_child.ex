defmodule KlassHero.Family.Application.Commands.Children.CreateChild do
  @moduledoc """
  Use case for creating a new child.

  Orchestrates domain validation and persistence through the repository port.
  When a parent_id is provided, the child is atomically linked to the guardian.
  """

  alias KlassHero.Family.Domain.Events.FamilyEvents
  alias KlassHero.Family.Domain.Models.Child
  alias KlassHero.Shared.CommandResult
  alias KlassHero.Shared.EventDispatchHelper

  @context KlassHero.Family
  @repository Application.compile_env!(:klass_hero, [:family, :for_storing_children])

  @doc """
  Creates a new child, optionally linking it to a guardian (parent).

  Expects `parent_id` in attrs to establish the guardian relationship.
  The child itself does not carry a parent_id; the relationship is
  managed through the children_guardians join table via the repository port.

  Returns:
  - `{:ok, Child.t()}` on success
  - `{:error, {:validation_error, errors}}` for domain validation failures
  - `{:error, changeset}` for persistence validation failures
  """
  def execute(attrs) when is_map(attrs) do
    {parent_id, child_attrs} = Map.pop(attrs, :parent_id)
    child_attrs = Map.put_new(child_attrs, :id, Ecto.UUID.generate())

    with {:ok, _validated} <- Child.new(child_attrs),
         {:ok, persisted} <- persist_child(child_attrs, parent_id) do
      dispatch_child_created(persisted, parent_id)
      {:ok, persisted}
    else
      result -> CommandResult.wrap_validation_errors(result)
    end
  end

  defp dispatch_child_created(child, parent_id) do
    FamilyEvents.child_created(child.id, %{
      child_id: child.id,
      parent_id: parent_id,
      first_name: child.first_name,
      last_name: child.last_name
    })
    |> EventDispatchHelper.dispatch(@context)
  end

  defp persist_child(attrs, nil), do: @repository.create(attrs)
  defp persist_child(attrs, guardian_id), do: @repository.create_with_guardian(attrs, guardian_id)
end
