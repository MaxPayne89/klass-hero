defmodule KlassHero.Enrollment.Adapters.Driven.ACL.ParentInfoACL do
  @moduledoc """
  ACL adapter that translates Family context parent data into
  Enrollment's parent info representation.

  The Enrollment context never directly depends on Family domain models.
  This adapter queries the Family facade and maps only the fields
  needed for roster messaging into plain maps.
  """

  @behaviour KlassHero.Enrollment.Domain.Ports.ForResolvingParentInfo

  use KlassHero.Shared.Tracing

  alias KlassHero.Family

  @impl true
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
end
