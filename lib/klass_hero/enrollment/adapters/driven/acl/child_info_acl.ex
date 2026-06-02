defmodule KlassHero.Enrollment.Adapters.Driven.ACL.ChildInfoACL do
  @moduledoc """
  ACL adapter that translates Family context child data into
  Enrollment's child info representation.

  The Enrollment context never directly depends on Family domain models.
  This adapter queries the Family facade and maps only the fields
  needed for roster display into plain maps.
  """

  @behaviour KlassHero.Enrollment.Domain.Ports.ForResolvingChildInfo

  use KlassHero.Shared.Tracing

  alias KlassHero.Family

  @impl true
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
end
