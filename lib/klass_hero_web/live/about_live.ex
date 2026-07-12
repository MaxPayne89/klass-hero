defmodule KlassHeroWeb.AboutLive do
  use KlassHeroWeb, :live_view

  import KlassHeroWeb.MarketingComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: gettext("About Us"),
       active_nav: :about
     )}
  end

  defp values do
    [
      %{
        icon: "hero-shield-check",
        title: gettext("Safety First"),
        description: gettext("All instructors are background-checked and verified.")
      },
      %{
        icon: "hero-sparkles",
        title: gettext("Sustainability"),
        description: gettext("Supporting local programs and eco-conscious practices.")
      },
      %{
        icon: "hero-user-group",
        title: gettext("Community"),
        description: gettext("Building connections between families and local instructors.")
      }
    ]
  end

  defp founders do
    [
      %{
        initials: "SC",
        name: "Shane",
        role: gettext("Founder & CEO"),
        bio:
          gettext(
            "A decade-plus coaching and running youth activity programs in Berlin. Built Prime Youth before founding Klass Hero."
          )
      },
      %{
        initials: "MP",
        name: "Max Pergl",
        role: gettext("Co-founder & CTO"),
        bio:
          gettext(
            "Full-stack developer. Partner of a teacher who saw the gap between great educators and good infrastructure."
          )
      },
      %{
        initials: "KP",
        name: "Konstantin Pergl",
        role: gettext("CFO"),
        bio:
          gettext(
            "Brings the financial rigour and strategic planning needed for the German market and long-term provider stability."
          )
      },
      %{
        initials: "LC",
        name: "Laurie Camargo",
        role: gettext("Head of Trust & Quality (joining)"),
        bio:
          gettext(
            "Mother and child-safety specialist with 10+ years in quality assurance. Architecting our Safety-First Verification engine."
          )
      }
    ]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.mk_page_hero id="mk-about-hero" pill={gettext("Our Mission")}>
      <:title>
        {gettext("To modernize how Berlin")}
        <span class="bg-hero-yellow-500 px-2 rounded-lg">{gettext("families")}</span>
        {gettext("discover & engage with children's programs")}
      </:title>
      <:lede>
        {gettext(
          "We're parents, brothers, and partners of educators — building the infrastructure that helps every child learn and thrive."
        )}
      </:lede>
    </.mk_page_hero>

    <.mk_about_values
      pill={gettext("Built for Berlin")}
      title={gettext("Built for Berlin Families")}
      paragraphs={[
        gettext(
          "We understand the unique needs of Berlin's diverse families. Our platform connects you with vetted, high-quality programs that match your values and your children's interests."
        ),
        gettext(
          "From sports to arts, technology to languages, we make it easy to discover enriching activities that fit your family's schedule and budget."
        )
      ]}
      quote={
        gettext(
          "We are Klass Hero — parents, brothers, and partners of educators — building the infrastructure that helps every child learn and thrive."
        )
      }
      values={values()}
    />

    <.mk_about_vetting
      pill={gettext("Our 6-Step Vetting Process")}
      title={gettext("Every Hero. Every step.")}
      subtitle={gettext("Rigorous screening so families never wonder who's leading the room.")}
      steps={vetting_steps()}
    />

    <.mk_about_story
      pill={gettext("The Klass Hero Story")}
      title={gettext("Built by parents and educators for more learning opportunities.")}
      founders={founders()}
    >
      <:body>
        <p>
          <span class="font-bold text-hero-black">Shane</span>
          {gettext(
            "spent over a decade as a coach and youth activity provider in Berlin, building Prime Youth — a community of providers, schools, and parents dedicated to giving children the best possible experiences. But one pattern kept emerging: the administrative burden of managing bookings, payments, and compliance was getting in everyone's way."
          )}
        </p>
        <p>
          {gettext("In 2025, Shane connected with his friend")}
          <span class="font-bold text-hero-black">Max Pergl</span>
          {gettext(
            ", a full-stack developer who shared a unique perspective. Both Shane and Max are partners of teachers who wanted to extend their expertise beyond the classroom — but without the time to manage the operational side on their own."
          )}
        </p>
        <p>
          {gettext(
            "Klass Hero was built to solve exactly that. A comprehensive operational platform that empowers educators to spend less time on paperwork and more time inspiring children."
          )}
        </p>
        <p>
          <span class="font-bold text-hero-black">Konstantin Pergl</span>
          {gettext(
            ", Max's brother, joined as CFO, bringing the financial rigour and strategic planning needed to navigate the German market and ensure long-term stability for every provider on the platform. To lead trust and quality,"
          )}
          <span class="font-bold text-hero-black">Laurie Camargo</span>
          {gettext(
            "— a mother with over a decade of experience in child safety and quality assurance — will join to architect our Safety-First Verification engine."
          )}
        </p>
      </:body>
    </.mk_about_story>

    <.mk_cta_section id="mk-about-cta" title={gettext("Ready to join the movement?")}>
      <:cta>
        <div class="flex gap-3 justify-center flex-wrap">
          <.link navigate={~p"/users/register"}>
            <.kh_button variant={:primary} size={:lg}>
              {gettext("Get Started Today →")}
            </.kh_button>
          </.link>
          <.link navigate={~p"/contact"}>
            <.kh_button variant={:ghost} size={:lg}>{gettext("Talk to us")}</.kh_button>
          </.link>
        </div>
      </:cta>
    </.mk_cta_section>
    """
  end
end
