defmodule KlassHeroWeb.Presenters.VettingChecklistPresenter do
  @moduledoc """
  Transforms a `VettingChecklist` read model into display data for the onboarding checklist:
  per-step copy + icon, a status badge (tone + label), and the contextual action.

  Pure presentation — no data access. The LiveView decides how to render each action kind:
  `:identity` is the inline Stripe widget; `:navigate_documents` / `:navigate_agreement` deep-link
  to the existing edit panels; `:none` renders no action (approved or awaiting review).
  """

  use Gettext, backend: KlassHeroWeb.Gettext

  alias KlassHero.Provider.VettingChecklist
  alias KlassHero.Provider.VettingStepView

  @type badge :: %{tone: atom(), label: String.t()}
  @type action :: %{
          kind:
            :identity
            | :responsible_person
            | :business_registration
            | :insurance
            | :navigate_documents
            | :navigate_agreement
            | :none,
          label: String.t() | nil
        }

  @doc """
  Flattens a checklist into a list of display rows ready for the template — copy, icon, badge,
  action, and the raw status/reason needed to render rejection feedback. Order matches the track.
  """
  @spec rows(VettingChecklist.t()) :: [map()]
  def rows(%VettingChecklist{steps: steps}) do
    Enum.map(steps, fn %VettingStepView{} = step ->
      meta = step_meta(step.key)
      badge = badge(step.ui_status)
      action = action(step)

      %{
        key: step.key,
        title: meta.title,
        description: meta.description,
        icon: meta.icon,
        gradient: meta.gradient,
        badge_tone: badge.tone,
        badge_label: badge.label,
        action_kind: action.kind,
        action_label: action.label,
        action_anchor: action[:anchor],
        ui_status: step.ui_status,
        rejection_reason: step.rejection_reason
      }
    end)
  end

  @doc "Per-step display copy and icon for the given step key."
  @spec step_meta(atom()) :: %{title: String.t(), description: String.t(), icon: String.t(), gradient: atom()}
  def step_meta(:identity),
    do: %{
      title: gettext("Identity & age verification"),
      description: gettext("Confirm who you are with our partner Stripe."),
      icon: "hero-identification",
      gradient: :primary
    }

  def step_meta(:experience),
    do: %{
      title: gettext("Experience"),
      description: gettext("Show relevant experience working with children."),
      icon: "hero-academic-cap",
      gradient: :cool
    }

  def step_meta(:background),
    do: %{
      title: gettext("Background check"),
      description: gettext("Upload a current background check."),
      icon: "hero-shield-check",
      gradient: :safety
    }

  def step_meta(:video),
    do: %{
      title: gettext("Video screening"),
      description: gettext("A short video so we can meet you."),
      icon: "hero-video-camera",
      gradient: :art
    }

  def step_meta(:safeguarding),
    do: %{
      title: gettext("Safeguarding"),
      description: gettext("Upload your safeguarding certificate."),
      icon: "hero-lock-closed",
      gradient: :safety
    }

  def step_meta(:community_agreement),
    do: %{
      title: gettext("Community standards"),
      description: gettext("Read and sign the community standards agreement."),
      icon: "hero-hand-raised",
      gradient: :comic
    }

  def step_meta(:responsible_person_identity),
    do: %{
      title: gettext("Responsible person"),
      description: gettext("Verify the owner or director accountable for the business."),
      icon: "hero-identification",
      gradient: :primary
    }

  def step_meta(:business_registration),
    do: %{
      title: gettext("Business registration"),
      description: gettext("Upload your business registration document."),
      icon: "hero-building-office-2",
      gradient: :cool
    }

  def step_meta(:insurance),
    do: %{
      title: gettext("Insurance"),
      description: gettext("Upload your liability insurance certificate."),
      icon: "hero-shield-check",
      gradient: :safety
    }

  def step_meta(:staff_attestation),
    do: %{
      title: gettext("Staff attestation"),
      description: gettext("Attest that your staff meet child-safety requirements."),
      icon: "hero-user-group",
      gradient: :comic
    }

  @doc "Badge tone + label for a step's displayed status."
  @spec badge(VettingStepView.ui_status()) :: badge()
  def badge(:approved), do: %{tone: :success, label: gettext("Approved")}
  def badge(:submitted), do: %{tone: :warning, label: gettext("Under review")}
  def badge(:rejected), do: %{tone: :error, label: gettext("Needs changes")}
  def badge(:not_started), do: %{tone: :outline, label: gettext("Not started")}

  @doc """
  The contextual action for a step. Identity is always its inline widget; document and agreement
  steps offer an action only when there is something for the provider to do (not approved, not
  awaiting review).
  """
  @spec action(VettingStepView.t()) :: action()
  # The business identity step captures a Responsible Person first (ADR-0010) — its own widget,
  # distinct from the individual bare-identity widget. Keyed above the generic stripe_identity clause.
  def action(%VettingStepView{key: :responsible_person_identity}), do: %{kind: :responsible_person, label: nil}

  # Business registration (B2) captures structured fields + document in a dedicated widget that
  # renders in every state, so it forks above the generic document and :none clauses.
  def action(%VettingStepView{key: :business_registration}), do: %{kind: :business_registration, label: nil}

  # Insurance (B3) captures the certificate + its policy expiry date in a dedicated widget that
  # renders in every state (like business registration), so it forks above the generic document
  # clause that would otherwise deep-link it to the shared documents panel.
  def action(%VettingStepView{key: :insurance}), do: %{kind: :insurance, label: nil}

  def action(%VettingStepView{completed_via: {:stripe_identity}}), do: %{kind: :identity, label: nil}

  def action(%VettingStepView{ui_status: status}) when status in [:approved, :submitted], do: %{kind: :none, label: nil}

  def action(%VettingStepView{completed_via: {:document, _type}, ui_status: status}),
    do: %{kind: :navigate_documents, label: document_label(status)}

  def action(%VettingStepView{completed_via: {:signed_agreement, kind}, ui_status: status}),
    do: %{kind: :navigate_agreement, label: agreement_label(status), anchor: agreement_anchor(kind)}

  @doc "The headline copy for the profile-locked banner."
  @spec locked_summary(VettingChecklist.t()) :: String.t()
  def locked_summary(%VettingChecklist{approved_count: approved, total_count: total}) do
    gettext("Complete all steps to publish programs. %{approved} of %{total} approved.",
      approved: approved,
      total: total
    )
  end

  defp document_label(:rejected), do: gettext("Resubmit")
  defp document_label(_), do: gettext("Upload")

  defp agreement_label(_), do: gettext("Review & sign")

  # Deep-link target for each signed-agreement checklist row — each agreement step has its own
  # in-page panel, so the two must not share one anchor. Kept here (not the LiveView) so the
  # step -> UI-target mapping lives in one place, alongside the rest of the row's action metadata.
  defp agreement_anchor(:community_agreement), do: "#community-agreement-form"
  defp agreement_anchor(:staff_attestation), do: "#staff-attestation-form"
end
