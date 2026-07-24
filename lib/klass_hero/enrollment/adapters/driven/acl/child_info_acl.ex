defmodule KlassHero.Enrollment.Adapters.Driven.ACL.ChildInfoACL do
  @moduledoc """
  ACL adapter that translates Family context child data into
  Enrollment's child info representation.

  The Enrollment context never directly depends on Family domain models.
  This adapter queries the Family facade and maps only the fields
  needed for roster display into plain maps.
  """

  use KlassHero.Shared.Tracing

  alias KlassHero.Family

  def get_children_by_ids([]), do: []

  def get_children_by_ids(child_ids) when is_list(child_ids) do
    acl_span source: "enrollment", target: "family" do
      child_ids
      |> Family.get_children_by_ids()
      |> Enum.map(fn child ->
        %{
          id: child.id,
          first_name: child.first_name,
          last_name: child.last_name
        }
      end)
    end
  end

  @doc """
  Returns `true` when `child_id` is a child of `parent_id` (guardian link exists).

  Used by the enrollment create flow to enforce that a parent can only enroll
  their own children — closes a cross-family IDOR on `child_id`.
  """
  def child_belongs_to_parent?(child_id, parent_id) when is_binary(child_id) and is_binary(parent_id) do
    acl_span source: "enrollment", target: "family" do
      Family.child_belongs_to_parent?(child_id, parent_id)
    end
  end
end
