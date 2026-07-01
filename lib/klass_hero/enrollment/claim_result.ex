defmodule KlassHero.Enrollment.ClaimResult do
  @moduledoc """
  Result of `ClaimInvite.execute/1`.

  Carries the resolved user (new or existing), the user-type discriminator,
  and the originating invite — all three are required for callers and
  downstream UI flows.
  """

  alias KlassHero.Enrollment.BulkEnrollmentInvite

  @enforce_keys [:user_type, :user, :invite]
  defstruct [:user_type, :user, :invite]

  @type user_type :: :new_user | :existing_user

  @type t :: %__MODULE__{
          user_type: user_type(),
          user: map(),
          invite: BulkEnrollmentInvite.t()
        }
end
