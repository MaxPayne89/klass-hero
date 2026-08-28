defmodule KlassHero.Participation.ChildInfoResolver do
  @moduledoc """
  ACL adapter resolving child info from the Family context.

  Always returns name fields; returns safety fields (`allergies`, `support_needs`,
  `emergency_contact`) only when `"provider_data_sharing"` consent is active.

  Maps Family's `:not_found` → `:child_not_found` for Participation semantics.
  """

  alias KlassHero.Family

  @consent_type "provider_data_sharing"

  def resolve_child_info(child_id) when is_binary(child_id) do
    case Family.get_child_by_id(child_id) do
      {:ok, child} ->
        has_consent? = Family.child_has_active_consent?(child_id, @consent_type)

        child_info = %{
          first_name: child.first_name,
          last_name: child.last_name,
          allergies: if(has_consent?, do: child.allergies),
          support_needs: if(has_consent?, do: child.support_needs),
          emergency_contact: if(has_consent?, do: child.emergency_contact),
          has_consent?: has_consent?
        }

        {:ok, child_info}

      {:error, :not_found} ->
        {:error, :child_not_found}
    end
  end

  def resolve_children_info(child_ids) when is_list(child_ids) do
    children = Family.get_children_by_ids(child_ids)
    consented_ids = Family.children_with_active_consents(child_ids, @consent_type)

    Map.new(children, fn child ->
      has_consent? = MapSet.member?(consented_ids, child.id)

      info = %{
        first_name: child.first_name,
        last_name: child.last_name,
        allergies: if(has_consent?, do: child.allergies),
        support_needs: if(has_consent?, do: child.support_needs),
        emergency_contact: if(has_consent?, do: child.emergency_contact),
        has_consent?: has_consent?
      }

      {child.id, info}
    end)
  end
end
