defmodule KlassHero.Provider.Vetting do
  @moduledoc """
  Vetting track policy: the ordered, composable set of `StepDefinition`s a Provider
  must complete, selected by `entity_type`. Pure domain policy — no persistence,
  no side effects.

  Track composition (which steps, in what order, with which prerequisites) lives
  here, in code, so changes are version-controlled and reviewed. The `:individual`
  track is the 6-step spine; the `:business` track is a follow-up and currently
  carries only its document steps.

  See `docs/6-step-verification-process.md` for the target catalog and
  `docs/adr/0008-provider-vetting-is-a-composable-step-engine.md` for the engine decision.

  Command and query functions that persist and read Vetting Cases are added to this
  module in later parts of the engine slice; `track/1` is the pure policy they build on.
  """

  alias KlassHero.Provider.StepDefinition

  @individual_track [
    %StepDefinition{key: :identity, completed_via: {:stripe_identity}, admin_review: false},
    %StepDefinition{key: :experience, completed_via: {:document, "experience_validation"}, admin_review: true},
    %StepDefinition{key: :background, completed_via: {:document, "background_check"}, admin_review: true},
    %StepDefinition{key: :video, completed_via: {:document, "video_screening"}, admin_review: true},
    %StepDefinition{key: :safeguarding, completed_via: {:document, "safeguarding_certificate"}, admin_review: true},
    %StepDefinition{
      key: :community_agreement,
      completed_via: {:signed_agreement, :community_agreement},
      admin_review: false
    }
  ]

  @business_track [
    %StepDefinition{
      key: :business_registration,
      completed_via: {:document, "business_registration"},
      admin_review: true
    },
    %StepDefinition{key: :insurance, completed_via: {:document, "insurance_certificate"}, admin_review: true}
  ]

  @doc """
  Returns the ordered list of `StepDefinition`s for the given `entity_type`.
  """
  @spec track(:individual | :business) :: [StepDefinition.t()]
  def track(:individual), do: @individual_track
  def track(:business), do: @business_track
end
