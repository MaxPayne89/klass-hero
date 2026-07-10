defmodule KlassHero.Provider.VettingChecklist do
  @moduledoc """
  Display-optimized view of a provider's whole vetting case for the onboarding checklist page.

  Carries the overall lifecycle plus the ordered per-step views and the approved/total counts
  used by the "profile locked" banner. Pure display struct — no business logic.
  """

  alias KlassHero.Provider.VettingStepView

  @type t :: %__MODULE__{
          lifecycle: :not_started | :in_progress | :verified,
          entity_type: :individual | :business,
          verified?: boolean(),
          approved_count: non_neg_integer(),
          total_count: non_neg_integer(),
          steps: [VettingStepView.t()]
        }

  @enforce_keys [:lifecycle, :entity_type, :verified?, :approved_count, :total_count, :steps]
  defstruct [:lifecycle, :entity_type, :verified?, :approved_count, :total_count, steps: []]
end
