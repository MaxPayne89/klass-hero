defmodule KlassHeroWeb.HomeLive do
  use KlassHeroWeb, :live_view

  import KlassHeroWeb.MarketingComponents

  alias KlassHero.ProgramCatalog
  alias KlassHero.ProgramCatalog.ProgramListing
  alias KlassHeroWeb.Presenters.ProgramPresenter
  alias KlassHeroWeb.Theme

  @impl true
  def mount(_params, _session, socket) do
    featured = ProgramCatalog.list_featured_programs()
    featured_maps = Enum.map(featured, &listing_to_card_map/1)
    trending_tags = ProgramCatalog.trending_searches()

    socket =
      socket
      |> assign(
        page_title: gettext("Klass Hero - Connecting Families with Trusted Youth Educators"),
        trending_tags: trending_tags,
        active_nav: :home
      )
      |> stream(:featured_programs, featured_maps)

    {:ok, socket}
  end

  @impl true
  def handle_event("explore_programs", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/programs")}
  end

  @impl true
  def handle_event("search", %{"search" => query}, socket) do
    query = String.trim(query)

    if query == "" do
      {:noreply, socket}
    else
      {:noreply, push_navigate(socket, to: ~p"/programs?q=#{query}")}
    end
  end

  @impl true
  def handle_event("tag_search", %{"tag" => tag}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/programs?q=#{tag}")}
  end

  @impl true
  def handle_event("view_program", %{"program-id" => program_id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/programs/#{program_id}")}
  end

  # No provider row here on purpose: the home page renders `mk_program_card`, a
  # marketing card that shows no provider at all. Threading a name and trust state
  # into it would recreate exactly the write-only data #1195 deleted. Surfacing
  # verification here needs a design decision about the marketing card first.
  defp listing_to_card_map(%ProgramListing{} = program) do
    %{
      id: program.id,
      title: program.title,
      description: program.description,
      category: ProgramPresenter.format_category_for_display(program.category),
      age_range: program.age_range,
      price: ProgramPresenter.safe_decimal_to_float(program.price),
      period: program.pricing_period,
      cover_image_url: program.cover_image_url,
      meeting_days: program.meeting_days || [],
      meeting_start_time: program.meeting_start_time,
      meeting_end_time: program.meeting_end_time,
      start_date: program.start_date,
      end_date: program.end_date,
      gradient_class: Theme.gradient(:primary),
      icon_name: ProgramPresenter.icon_name(program.category)
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.mk_hero trending_tags={@trending_tags} />

    <.mk_featured stream={@streams.featured_programs} />

    <.mk_features />

    <.mk_provider_cta />

    <.mk_founder />

    <.mk_faq subtitle={gettext("Everything you need to know about Klass Hero.")}>
      <.mk_faq_item
        id="faq-1"
        question={gettext("How does the 6-step provider vetting process work?")}
      >
        <p>
          {gettext(
            "Every provider completes identity and age verification, experience validation, an extended background check, video screening, child safeguarding training, and agreement to our Community Guidelines before being approved."
          )}
        </p>
      </.mk_faq_item>

      <.mk_faq_item
        id="faq-2"
        question={gettext("Can I list my programs on Klass Hero and what does it cost?")}
      >
        <p class="mb-3">{gettext("Yes! Register for free and start listing immediately.")}</p>
        <p class="font-semibold mb-1 text-hero-black">{gettext("What You Can List:")}</p>
        <ul class="list-disc list-inside mb-3 space-y-1">
          <li>{gettext("Regular classes and courses (weekly/monthly)")}</li>
          <li>{gettext("Camps and holiday programs")}</li>
          <li>{gettext("Workshops and one-time events")}</li>
          <li>{gettext("Private lessons and tutoring")}</li>
        </ul>
        <p class="font-semibold mb-1 text-hero-black">{gettext("Pricing:")}</p>
        <p class="mb-3">
          {gettext(
            "Joining Klass Hero costs nothing — unlimited programs, your whole team, all media, and direct parent messaging are included for everyone. A simple success-based fee on bookings made through the platform is coming; we'll share the details transparently before it launches."
          )}
        </p>
        <p class="mt-3">
          {gettext(
            "Every provider gets: Profile page, booking system, payment processing, messaging, and marketing to Berlin families."
          )}
        </p>
      </.mk_faq_item>

      <.mk_faq_item id="faq-3" question={gettext("How does the booking system work?")}>
        <p class="mb-3">{gettext("Simple and automated - we handle everything.")}</p>
        <p class="font-semibold mb-1 text-hero-black">{gettext("When Someone Books:")}</p>
        <ol class="list-decimal list-inside mb-3 space-y-1">
          <li>{gettext("Parent books and pays through Klass Hero (via Stripe)")}</li>
          <li>{gettext("You receive instant email with booking details and parent contact info")}</li>
          <li>{gettext("Parent receives confirmation with your contact details")}</li>
          <li>{gettext("Funds are immediately available in your Klass Hero account")}</li>
          <li>{gettext("You deliver the program")}</li>
        </ol>
        <p class="font-semibold mb-1 text-hero-black">{gettext("Payment Options for Parents:")}</p>
        <ul class="list-disc list-inside mb-3 space-y-1">
          <li>{gettext("Credit/debit card (Visa, Mastercard, Amex)")}</li>
          <li>{gettext("Apple Pay / Google Pay")}</li>
          <li>{gettext("SEPA direct debit")}</li>
          <li>{gettext("Klarna (pay later options)")}</li>
        </ul>
        <p class="mb-3">{gettext("All payments processed securely through Stripe.")}</p>
        <p class="font-semibold mb-1 text-hero-black">{gettext("How You Get Paid:")}</p>
        <ul class="list-disc list-inside mb-3 space-y-1">
          <li>
            {gettext(
              "Instant availability: Funds are in your Klass Hero balance immediately after booking"
            )}
          </li>
          <li>{gettext("Weekly payouts: Transferred to your bank account every Friday")}</li>
          <li>{gettext("Or: Request instant payout anytime (minimum €50)")}</li>
          <li>{gettext("Platform fee automatically deducted when parent pays")}</li>
        </ul>
        <p class="font-semibold mb-1 text-hero-black">{gettext("Why This Works Better:")}</p>
        <ul class="list-disc list-inside mb-3 space-y-1">
          <li>{gettext("You get paid BEFORE delivering the program (no waiting)")}</li>
          <li>{gettext("Parents pay upfront when booking (reduces no-shows by 85%)")}</li>
          <li>{gettext("No chasing payments or sending invoices")}</li>
          <li>{gettext("No risk of non-payment")}</li>
          <li>{gettext("Automatic fee calculation (no surprises)")}</li>
        </ul>
        <p class="font-semibold mb-1 text-hero-black">{gettext("Track Everything:")}</p>
        <ul class="list-disc list-inside space-y-1">
          <li>{gettext("Real-time dashboard shows all bookings and available balance")}</li>
          <li>{gettext("Export participant lists anytime")}</li>
          <li>{gettext("See payment history and upcoming payouts")}</li>
          <li>{gettext("Download monthly statements for taxes")}</li>
        </ul>
      </.mk_faq_item>

      <.mk_faq_item id="faq-4" question={gettext("Is Klass Hero free for parents to use?")}>
        <p>
          {gettext("Yes! Browsing and booking are completely free. No subscription, no booking fees.")}
        </p>
      </.mk_faq_item>

      <.mk_faq_item id="faq-5" question={gettext("Do I need an account to book?")}>
        <p>
          {gettext("Yes, you need a free account to complete a booking and manage your reservations.")}
        </p>
      </.mk_faq_item>

      <.mk_faq_item id="faq-6" question={gettext("Can I change my booking date?")}>
        <p>
          {gettext(
            "Contact the provider directly (details in confirmation email). Most providers are flexible if you ask in advance."
          )}
        </p>
      </.mk_faq_item>

      <.mk_faq_item id="faq-7" question={gettext("What if my child gets sick?")}>
        <p>
          {gettext(
            "Email the provider and us (support@mail.klasshero.com) as soon as you can — we'll help you and the provider work it out."
          )}
        </p>
      </.mk_faq_item>

      <.mk_faq_item id="faq-8" question={gettext("Where is Klass Hero available?")}>
        <p>
          {gettext("Currently serving Berlin, with expansion to other German cities coming soon.")}
        </p>
      </.mk_faq_item>

      <.mk_faq_item id="faq-9" question={gettext("Can I buy a gift voucher?")}>
        <p>
          {gettext(
            "Coming soon! Sign up for our newsletter to be notified when gift vouchers launch."
          )}
        </p>
      </.mk_faq_item>
    </.mk_faq>
    """
  end
end
