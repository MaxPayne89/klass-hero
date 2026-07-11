defmodule KlassHeroWeb.TrustSafetyLive do
  use KlassHeroWeb, :live_view

  import KlassHeroWeb.MarketingComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: gettext("Trust & Safety"),
       active_nav: :trust
     )}
  end

  defp verification_steps do
    [
      %{
        icon: "hero-identification",
        title: gettext("Identity & Age Verification"),
        description:
          gettext(
            "All providers must be 18 years or older, ensuring legal accountability and professional responsibility."
          )
      },
      %{
        icon: "hero-academic-cap",
        title: gettext("Experience Validation"),
        description:
          gettext(
            "Providers must demonstrate at least one year of experience working with children in their area of expertise."
          )
      },
      %{
        icon: "hero-shield-check",
        title: gettext("Extended Background Checks"),
        description:
          gettext(
            "Each provider submits an extended police background check, confirming their eligibility to work safely with minors."
          )
      },
      %{
        icon: "hero-video-camera",
        title: gettext("Video Screening"),
        description:
          gettext(
            "Applicants submit a short recorded video (max 2 minutes) so we can assess communication skills and alignment with our values before approving their profile."
          )
      },
      %{
        icon: "hero-heart",
        title: gettext("Child Safeguarding Training"),
        description:
          gettext(
            "All Heroes must hold or complete a recognized child safeguarding course, ensuring up-to-date knowledge."
          )
      },
      %{
        icon: "hero-check-circle",
        title: gettext("Community Standards Agreement"),
        description:
          gettext(
            "Every provider agrees to follow our Community Guidelines, defining expectations around professionalism."
          )
      }
    ]
  end

  defp commitment_items do
    [
      gettext("Protect children and families"),
      gettext("Support schools and institutions with reliable providers"),
      gettext("Uphold professional and ethical teaching practices"),
      gettext("Create long-term trust across our community")
    ]
  end

  defp accountability_items do
    [
      gettext("Monitoring provider activity and feedback"),
      gettext("Enforcing platform standards and guidelines"),
      gettext("Reviewing concerns or reports promptly and seriously"),
      gettext("Taking action when standards are not met")
    ]
  end

  defp vetted_stats do
    [
      {"100%", gettext("Vetted")},
      {"6-step", gettext("Process")},
      # Per product call: third stat reads just `Reporting` as the big yellow
      # display value, no separate label — avoids implying 24/7 staffed support
      # while keeping the three-column visual balance.
      {gettext("Reporting"), nil}
    ]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.mk_page_hero id="mk-trust-hero" eyebrow_icon="hero-shield-check" eyebrow_gradient={:cool}>
      <:title>
        {gettext("Trust &")}
        <span class="bg-hero-yellow-500 px-2 rounded-lg">{gettext("Safety")}</span>
      </:title>
      <:lede>
        {gettext(
          "At Klass Hero, trust isn't a feature — it's the foundation of everything we do. We connect families, schools, and organizations with qualified, vetted, and safety-verified educators."
        )}
      </:lede>
    </.mk_page_hero>

    <.mk_trust_commitment
      title={gettext("Our commitment to child safety")}
      lede={
        gettext(
          "We believe children thrive best in environments that are safe, respectful, and professionally led. That's why Klass Hero applies a multi-layered safety and verification framework before any provider can offer sessions on our platform."
        )
      }
      commitments={commitment_items()}
      vetted_title={gettext("Every Hero, carefully reviewed.")}
      vetted_lede={
        gettext(
          "From academic tutoring to sports, arts, and enrichment programs, every provider on Klass Hero is carefully reviewed to ensure they meet our high standards for child safety, professionalism, and educational quality."
        )
      }
      stats={vetted_stats()}
    />

    <.mk_trust_verification
      title={gettext("Six checks. No shortcuts.")}
      subtitle={
        gettext(
          "Every educator and enrichment professional completes a 6-step verification process before being approved."
        )
      }
      steps={verification_steps()}
    />

    <.mk_trust_accountability
      title={gettext("Quality & accountability — always on.")}
      lede={
        gettext(
          "Trust doesn't stop at onboarding. Klass Hero continuously works to maintain a safe and high-quality ecosystem by:"
        )
      }
      items={accountability_items()}
      warning={
        gettext(
          "Providers who fail to uphold our expectations may be suspended or removed from the platform."
        )
      }
    />

    <.mk_cta_section
      id="mk-trust-cta"
      title={gettext("Have questions?")}
      lede={
        gettext(
          "If you'd like to learn more about our Trust & Safety standards or provider verification process, we're happy to help."
        )
      }
      tagline={gettext("Trust is earned. Safety is non-negotiable.")}
      sub_tagline={gettext("And at Klass Hero, both come standard.")}
    >
      <:cta>
        <.link navigate={~p"/contact"}>
          <.kh_button variant={:primary} size={:lg}>{gettext("Contact Us →")}</.kh_button>
        </.link>
      </:cta>
    </.mk_cta_section>
    """
  end
end
