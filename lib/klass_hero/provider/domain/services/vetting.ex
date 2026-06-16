defmodule KlassHero.Provider.Domain.Services.Vetting do
  @moduledoc """
  Vetting track policy: the ordered, composable set of `StepDefinition`s a Provider must
  complete, selected by `entity_type`. Pure domain policy — no persistence, no side effects.

  Track composition (which steps, in what order, with which prerequisites) lives here, in code,
  so changes are version-controlled and reviewed. This is the spine: only document-evidence
  steps are wired today; later slices add the Stripe identity, video, community-agreement and
  attestation steps to their tracks alongside the evidence kinds that complete them.

  See `docs/6-step-verification-process.md` for the target catalog and
  `docs/adr/0006-provider-vetting-is-a-composable-step-engine.md` for the engine decision.
  """

  alias KlassHero.Provider.Domain.Models.StepDefinition

  @individual_track [
    %StepDefinition{key: :experience, completed_via: {:document, "experience_validation"}, admin_review?: true},
    %StepDefinition{key: :background, completed_via: {:document, "background_check"}, admin_review?: true},
    %StepDefinition{key: :safeguarding, completed_via: {:document, "safeguarding_certificate"}, admin_review?: true}
  ]

  @business_track [
    %StepDefinition{
      key: :business_registration,
      completed_via: {:document, "business_registration"},
      admin_review?: true
    },
    %StepDefinition{key: :insurance, completed_via: {:document, "insurance_certificate"}, admin_review?: true}
  ]

  @doc """
  Returns the ordered list of `StepDefinition`s for the given `entity_type`.
  """
  @spec track(:individual | :business) :: [StepDefinition.t()]
  def track(:individual), do: @individual_track
  def track(:business), do: @business_track
end
