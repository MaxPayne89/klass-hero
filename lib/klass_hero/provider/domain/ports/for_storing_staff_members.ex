defmodule KlassHero.Provider.Domain.Ports.ForStoringStaffMembers do
  @moduledoc """
  Write-only port for storing staff members in the Provider bounded context.

  Read operations have been moved to `ForQueryingStaffMembers`.

  Defines the contract for staff member write operations.
  Implemented by adapters in the infrastructure layer.
  """

  alias KlassHero.Provider.Domain.Models.StaffMember

  @callback create(attrs :: map()) ::
              {:ok, StaffMember.t()} | {:error, term()}

  @callback update(staff_member :: StaffMember.t()) ::
              {:ok, StaffMember.t()} | {:error, :not_found | term()}

  @callback delete(id :: binary()) ::
              :ok | {:error, :not_found}

  @callback touch_last_selected(user_id :: String.t(), provider_id :: String.t()) ::
              {:ok, :selected} | {:error, :not_staffed}
end
