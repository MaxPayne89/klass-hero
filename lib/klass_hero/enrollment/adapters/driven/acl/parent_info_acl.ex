defmodule KlassHero.Enrollment.Adapters.Driven.ACL.ParentInfoACL do
  @moduledoc """
  ACL adapter that translates Family context parent data into
  Enrollment's parent info representation.

  The Enrollment context never directly depends on Family domain models.
  This adapter queries the Family facade and maps only the fields
  needed for roster messaging into plain maps.
  """

  use KlassHero.Shared.Tracing

  alias KlassHero.Family

  def get_parents_by_ids([]), do: []

  def get_parents_by_ids(parent_ids) when is_list(parent_ids) do
    acl_span source: "enrollment", target: "family" do
      parent_ids
      |> Family.get_parents_by_ids()
      |> Enum.map(fn parent ->
        %{
          id: parent.id,
          identity_id: parent.identity_id
        }
      end)
    end
  end

  @doc """
  Resolves a Family parent's identity_id to their parent_id, or nil when no
  parent profile exists for the identity.
  """
  def resolve_identity_id(identity_id) when is_binary(identity_id) do
    acl_span source: "enrollment", target: "family" do
      case Family.get_parent_by_identity(identity_id) do
        {:ok, parent} -> parent.id
        {:error, :not_found} -> nil
      end
    end
  end
end
