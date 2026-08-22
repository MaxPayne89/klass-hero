defmodule KlassHero.Provider.ReadModels.StaffMembership do
  @moduledoc """
  Read-model of one active employment of a user: a staff row plus the
  employing provider's business name.

  Powers the staff-context switcher (#969): the employer picker lists a
  user's memberships in the same selection order the scope resolution uses,
  so the head of the list is the employment the scope currently carries.
  Display-optimized; contains no business logic.
  """

  @typedoc "An active staff employment for display in the employer picker."
  @type t :: %__MODULE__{
          staff_member_id: String.t(),
          provider_id: String.t(),
          business_name: String.t()
        }

  @enforce_keys [:staff_member_id, :provider_id, :business_name]

  defstruct [
    :staff_member_id,
    :provider_id,
    :business_name
  ]
end
