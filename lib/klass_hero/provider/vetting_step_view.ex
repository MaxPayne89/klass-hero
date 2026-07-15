defmodule KlassHero.Provider.VettingStepView do
  @moduledoc """
  Display-optimized view of a single vetting step for the provider onboarding checklist.

  Combines the engine's `VerificationStep` status with the rejection/failure reason that lives
  on the step's evidence record (document, identity verification). Document and identity steps
  reset to `:not_started` on rejection (clearing the step's own reason), so `ui_status` is a
  *derived* status that re-surfaces `:rejected` when the latest evidence was rejected.

  Pure display struct — no business logic.
  """

  @type ui_status :: :not_started | :submitted | :approved | :rejected

  @type t :: %__MODULE__{
          key: atom(),
          ui_status: ui_status(),
          rejection_reason: String.t() | nil,
          admin_review: boolean(),
          completed_via: tuple(),
          dedicated: false | :widget | :command
        }

  @enforce_keys [:key, :ui_status, :completed_via]
  defstruct [:key, :ui_status, :rejection_reason, :completed_via, admin_review: false, dedicated: false]
end
