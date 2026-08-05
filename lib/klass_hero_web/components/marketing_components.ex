defmodule KlassHeroWeb.MarketingComponents do
  @moduledoc """
  Function components for the public marketing surface.

  Mirrors the `Mk*` primitives in `design_handoff/marketing/Sections.jsx`.
  Each section composes the shared `Kh*` vocabulary in
  `KlassHeroWeb.UIComponents` plus marketing-only chrome (header, footer)
  that is not used by the parent or provider apps.

  The legacy `hero_section` / `feature_card` / `provider_step_card` /
  `faq_item` components in `UIComponents` stay in place — they're still
  consumed by `AboutLive`, `ContactLive`, `ForProvidersLive`,
  `TrustSafetyLive`, `ProgramsLive`. Those pages migrate to the
  marketing chrome in follow-up PRs.
  """

  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: KlassHeroWeb.Endpoint,
    router: KlassHeroWeb.Router,
    statics: KlassHeroWeb.static_paths()

  use Gettext, backend: KlassHeroWeb.Gettext

  import KlassHeroWeb.UIComponents,
    only: [
      kh_logo: 1,
      kh_button: 1,
      kh_card: 1,
      kh_pill: 1,
      kh_icon_chip: 1,
      kh_trust_mark: 1,
      icon: 1
    ]

  alias KlassHeroWeb.Theme
  alias Phoenix.HTML.FormField
  alias Phoenix.LiveView.JS

  @nav_items [
    {:home, "Home", "/"},
    {:programs, "Programs", "/programs"},
    {:providers, "For Providers", "/for-providers"},
    {:trust, "Trust & Safety", "/trust-safety"},
    {:about, "About", "/about"},
    {:contact, "Contact", "/contact"}
  ]

  ## ---------------------------------------------------------------------------
  ## Header
  ## ---------------------------------------------------------------------------

  @doc """
  Sticky marketing header with horizontal nav, language pill, and auth CTAs.

  Maps to bundle's `MkHeader` (Sections.jsx:3). The mobile sheet is toggled
  client-side via `Phoenix.LiveView.JS` — no LiveView round-trip.
  """
  attr :active, :atom, default: :home, doc: "Highlighted nav key"
  attr :current_scope, :map, default: nil
  attr :locale, :string, default: "en"

  def mk_header(assigns) do
    assigns = assign(assigns, items: @nav_items)

    ~H"""
    <header class="sticky top-0 z-40 bg-white/90 backdrop-blur-md border-b border-[var(--border-light)]">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 h-16 lg:h-20 flex items-center justify-between gap-3">
        <.link navigate={~p"/"} class="flex items-center" aria-label="Klass Hero">
          <.kh_logo size={36} />
        </.link>

        <nav class="hidden lg:flex items-center gap-8" aria-label={gettext("Primary")}>
          <.link
            :for={{key, label, href} <- @items}
            navigate={href}
            class={[
              "text-[15px] font-semibold transition-colors",
              if(@active == key,
                do: "text-[var(--brand-primary-dark)]",
                else: "text-[var(--fg-body)] hover:text-[var(--brand-primary-dark)]"
              )
            ]}
          >
            {gettext_nav_label(label)}
          </.link>
        </nav>

        <div class="flex items-center gap-2">
          <div class="hidden lg:block">
            <KlassHeroWeb.Layouts.language_switcher locale={@locale} />
          </div>

          <%= if @current_scope && @current_scope.user do %>
            <.link
              navigate={KlassHeroWeb.UserAuth.dashboard_path(@current_scope.user)}
              class="hidden lg:inline-flex"
            >
              <.kh_button variant={:primary} size={:sm}>{gettext("Go to dashboard")}</.kh_button>
            </.link>
          <% else %>
            <.link href={~p"/users/log-in"} class="hidden lg:inline-flex">
              <.kh_button variant={:ghost} size={:sm}>{gettext("Sign in")}</.kh_button>
            </.link>
            <.link navigate={~p"/users/register"}>
              <.kh_button variant={:primary} size={:sm}>{gettext("Sign up")}</.kh_button>
            </.link>
          <% end %>

          <button
            type="button"
            phx-click={
              JS.toggle(to: "#mk-mobile-sheet")
              |> JS.toggle(to: "#mk-mobile-backdrop")
              |> JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "#mk-menu-toggle")
            }
            id="mk-menu-toggle"
            aria-label={gettext("Open menu")}
            aria-expanded="false"
            aria-controls="mk-mobile-sheet"
            class="lg:hidden flex items-center justify-center w-11 h-11 rounded-xl border border-[var(--border-light)] bg-white text-[var(--fg-primary)] hover:bg-[var(--hero-grey-100)] transition-colors"
          >
            <.icon name="hero-bars-3" class="w-6 h-6" />
          </button>
        </div>
      </div>

      <div
        id="mk-mobile-backdrop"
        phx-click={
          JS.hide(to: "#mk-mobile-sheet")
          |> JS.hide(to: "#mk-mobile-backdrop")
          |> JS.set_attribute({"aria-expanded", "false"}, to: "#mk-menu-toggle")
        }
        class="hidden lg:hidden fixed inset-0 top-16 bg-black/30 backdrop-blur-sm z-30"
      >
      </div>

      <div
        id="mk-mobile-sheet"
        class="hidden lg:hidden absolute left-0 right-0 top-full bg-white border-b border-[var(--border-light)] shadow-xl z-40 max-h-[calc(100vh-4rem)] overflow-y-auto"
      >
        <nav class="flex flex-col py-2" aria-label={gettext("Mobile primary")}>
          <.link
            :for={{key, label, href} <- @items}
            navigate={href}
            class={[
              "px-6 py-4 text-[17px] font-semibold border-b border-[var(--border-light)] last:border-b-0 transition-colors",
              if(@active == key,
                do: "text-[var(--brand-primary-dark)] bg-[var(--hero-pink-50)]",
                else: "text-[var(--fg-body)] hover:bg-[var(--hero-grey-100)]"
              )
            ]}
          >
            {gettext_nav_label(label)}
          </.link>
        </nav>

        <%= if @current_scope && @current_scope.user do %>
          <div class="px-6 py-4 border-t border-[var(--border-light)] bg-white">
            <p class="text-sm text-[var(--fg-muted)] mb-3">
              {gettext("Signed in as")}
              <span class="font-semibold text-hero-black">{@current_scope.user.email}</span>
            </p>
            <.link navigate={KlassHeroWeb.UserAuth.dashboard_path(@current_scope.user)}>
              <.kh_button variant={:primary} size={:md} class="!w-full">
                {gettext("Go to dashboard")}
              </.kh_button>
            </.link>
          </div>
        <% else %>
          <div class="px-6 py-5 border-t border-[var(--border-light)] bg-[var(--hero-cream-100)] flex flex-col gap-3">
            <.link href={~p"/users/log-in"}>
              <.kh_button variant={:ghost} size={:md} class="!w-full">
                {gettext("Sign in")}
              </.kh_button>
            </.link>
            <.link navigate={~p"/users/register"}>
              <.kh_button variant={:primary} size={:md} class="!w-full">
                {gettext("Sign up")}
              </.kh_button>
            </.link>
          </div>
        <% end %>

        <div class="px-6 py-4 border-t border-[var(--border-light)] flex items-center justify-center">
          <KlassHeroWeb.Layouts.language_switcher locale={@locale} />
        </div>
      </div>
    </header>
    """
  end

  # Translate nav labels through Gettext at call time.
  # Module attributes can't run gettext/1 (compile-time), so route via this
  # helper. Each branch is a literal string so `mix gettext.extract` finds it.
  defp gettext_nav_label("Home"), do: gettext("Home")
  defp gettext_nav_label("Programs"), do: gettext("Programs")
  defp gettext_nav_label("For Providers"), do: gettext("For Providers")
  defp gettext_nav_label("Trust & Safety"), do: gettext("Trust & Safety")
  defp gettext_nav_label("About"), do: gettext("About")
  defp gettext_nav_label("Contact"), do: gettext("Contact")
  defp gettext_nav_label(other), do: other

  ## ---------------------------------------------------------------------------
  ## Hero
  ## ---------------------------------------------------------------------------

  @doc """
  Marketing hero with gradient backdrop, blur orbs, eyebrow badge, headline
  with highlighted span, search form, trending tags, and wave divider.

  Maps to bundle's `MkHero` (Sections.jsx:98). Search form preserves the
  existing `phx-submit="search"` and tag-click `phx-click="tag_search"`
  handlers in `HomeLive`.
  """
  attr :trending_tags, :list, default: []

  def mk_hero(assigns) do
    ~H"""
    <section
      id="mk-hero"
      class="relative overflow-hidden bg-gradient-to-br from-hero-pink-50 via-white to-hero-blue-100 pt-16 pb-24 lg:pt-24 lg:pb-32"
    >
      <div class="absolute top-20 right-10 w-64 h-64 rounded-full bg-hero-yellow-500 opacity-30 blur-3xl pointer-events-none">
      </div>
      <div class="absolute bottom-10 left-10 w-72 h-72 rounded-full bg-hero-blue-400 opacity-20 blur-3xl pointer-events-none">
      </div>

      <div class="relative max-w-7xl mx-auto px-6 text-center">
        <div class="inline-flex items-center gap-2 mb-6 px-4 py-1.5 rounded-full bg-white shadow-sm border border-[var(--border-light)]">
          <.icon name="hero-sparkles" class="w-4 h-4 text-[var(--brand-primary-dark)]" />
          <span class="text-sm font-semibold">
            {gettext("Berlin's #1 network for youth educators")}
          </span>
        </div>

        <%!-- typography-lint-ignore: marketing hero headline scales fluidly via clamp() --%>
        <h1 class="font-display font-extrabold tracking-tight text-[clamp(40px,6vw,72px)] leading-[1.02] text-hero-black max-w-5xl mx-auto">
          {gettext("Connecting Families with")}
          <span class="bg-hero-yellow-500 px-2 rounded-lg">
            {gettext("Trusted Heroes")}
          </span>
          {gettext("for Our Youth")}
        </h1>

        <p class="mt-6 text-lg md:text-xl text-[var(--fg-muted-on-light)] max-w-2xl mx-auto leading-relaxed">
          {gettext(
            "Berlin's leading network for tutors, coaches, and camp providers — every one verified by our team."
          )}
        </p>

        <div class="mt-10 max-w-2xl mx-auto">
          <form id="home-search-form" phx-submit="search">
            <div class="flex items-center gap-2 p-2 bg-white rounded-full shadow-lg border border-[var(--border-light)]">
              <div class="flex-1 relative">
                <div class="absolute left-4 top-1/2 -translate-y-1/2 text-[var(--fg-muted)]">
                  <.icon name="hero-magnifying-glass" class="w-5 h-5" />
                </div>
                <input
                  type="text"
                  name="search"
                  placeholder={gettext("Search: coding, football, art...")}
                  class="w-full pl-11 pr-3 py-2.5 bg-transparent outline-none text-[15px] text-hero-black"
                />
              </div>
              <.kh_button type="submit" variant={:primary}>
                {gettext("Find Programs")}
              </.kh_button>
            </div>
          </form>

          <div
            :if={@trending_tags != []}
            class="mt-4 flex items-center justify-center gap-3 text-sm text-[var(--fg-muted)] flex-wrap"
          >
            <span>{gettext("Trending in Berlin:")}</span>
            <button
              :for={tag <- @trending_tags}
              type="button"
              phx-click="tag_search"
              phx-value-tag={tag}
              class="px-3 py-1 rounded-full bg-white border border-[var(--border-light)] cursor-pointer hover:border-[var(--brand-primary)] transition-colors"
            >
              {tag}
            </button>
          </div>
        </div>
      </div>

      <svg
        class="absolute -bottom-px left-0 w-full"
        viewBox="0 0 1440 80"
        preserveAspectRatio="none"
        style="height: 60px;"
        aria-hidden="true"
      >
        <path
          fill="#fff"
          d="M0,40 C240,80 480,0 720,20 C960,40 1200,80 1440,40 L1440,80 L0,80 Z"
        />
      </svg>
    </section>
    """
  end

  ## ---------------------------------------------------------------------------
  ## Featured programs
  ## ---------------------------------------------------------------------------

  @doc """
  Featured-programs section with pill label, headline, "View All" link, and
  3-up program-card grid.

  Maps to bundle's `MkFeatured` (Sections.jsx:147). Programs are passed as
  a LiveView stream so streaming + diff updates work correctly.
  """
  attr :stream, :any, required: true, doc: "LiveView stream of program maps"

  def mk_featured(assigns) do
    ~H"""
    <section id="mk-featured" class="py-16 lg:py-24 bg-white">
      <div class="max-w-7xl mx-auto px-6">
        <div class="flex items-end justify-between mb-10 flex-wrap gap-4">
          <div>
            <.kh_pill tone={:accent} class="mb-3">{gettext("Featured Programs")}</.kh_pill>
            <%!-- typography-lint-ignore: marketing section title intentionally larger than Theme.typography(:page_title) --%>
            <h2 class="font-display font-bold tracking-tight text-4xl lg:text-5xl text-hero-black">
              {gettext("Afterschool Adventures Await")}
            </h2>
            <p class="text-[var(--fg-muted)] text-lg mt-2">
              {gettext("Hand-picked programs this week across Berlin.")}
            </p>
          </div>
          <.link
            navigate={~p"/programs"}
            class={
              [
                "flex items-center gap-2 hover:gap-3 transition-all text-[var(--brand-primary-dark)]",
                # typography-lint-ignore: marketing accent link uses display font for visual emphasis
                "font-display font-bold"
              ]
            }
          >
            {gettext("View All Programs →")}
          </.link>
        </div>

        <div
          id="mk-featured-grid"
          phx-update="stream"
          class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6"
        >
          <%!-- `hidden only:block` shows the empty-state ONLY when the stream has no children.
                Pattern from .claude/rules/liveview.md — keeps the stream container stable. --%>
          <div
            id="mk-featured-empty"
            class="hidden only:block col-span-full text-center text-[var(--fg-muted)] py-16"
          >
            {gettext("No featured programs available right now. Check back soon.")}
          </div>
          <.mk_program_card
            :for={{dom_id, program} <- @stream}
            id={dom_id}
            program={program}
          />
        </div>
      </div>
    </section>
    """
  end

  @doc """
  Program card used inside `mk_featured`. Cover image (or gradient
  fallback), price + category pills, schedule chip, title, provider +
  age/period meta row, footer with `View →`. Click → existing
  `phx-click="view_program"`.

  The provider appears as a name and a compact trust mark in the meta row —
  no avatar, no bordered row, unlike `ProgramComponents.program_card/1`. The
  mark needs an adjacent name to read as a statement about the *provider*
  rather than about the listing, but the full row truncates the name at mobile
  width on this narrower card (#1224).
  """
  attr :id, :string, required: true
  attr :program, :map, required: true

  def mk_program_card(assigns) do
    ~H"""
    <.kh_card
      id={@id}
      data-program-id={@program.id}
      phx-click="view_program"
      phx-value-program-id={@program.id}
      class="overflow-hidden cursor-pointer hover:shadow-xl hover:-translate-y-1"
    >
      <div class={["relative h-44", !@program.cover_image_url && @program.gradient_class]}>
        <img
          :if={@program.cover_image_url}
          src={@program.cover_image_url}
          alt={@program.title}
          loading="lazy"
          class="absolute inset-0 w-full h-full object-cover"
        />
        <div :if={!@program.cover_image_url} class="absolute inset-0 bg-black/10"></div>
        <div :if={!@program.cover_image_url} class="absolute inset-0 flex items-center justify-center">
          <div class="w-16 h-16 rounded-full bg-white/20 backdrop-blur-sm flex items-center justify-center">
            <.icon name={@program.icon_name} class="w-8 h-8 text-white" />
          </div>
        </div>

        <div :if={@program.price} class="absolute top-3 left-3">
          <.kh_pill tone={:accent} class="!font-extrabold !text-sm !px-3">
            €{format_price(@program.price)}
          </.kh_pill>
        </div>
        <div class="absolute top-3 right-3">
          <.kh_pill tone={:dark}>{@program.category}</.kh_pill>
        </div>

        <div :if={schedule_label(@program)} class="absolute bottom-3 left-3">
          <div class="bg-white/90 backdrop-blur-sm px-3 py-1 rounded-full text-xs font-semibold text-hero-black flex items-center gap-1.5">
            <.icon name="hero-clock" class="w-3.5 h-3.5" />
            {schedule_label(@program)}
          </div>
        </div>
      </div>

      <div class="p-5">
        <h3 class="font-bold text-lg leading-snug text-hero-black line-clamp-2">
          {@program.title}
        </h3>
        <%!-- Provider gets its own line rather than joining the meta row below: at 375px
              the name plus the mark already fills the card, so sharing a line with the
              age range would wrap unpredictably (#1224). --%>
        <div
          :if={Map.get(@program, :provider_name)}
          class="mt-2 flex items-center gap-2 text-[13px] text-[var(--fg-muted)]"
        >
          <span class="truncate">{@program.provider_name}</span>
          <.kh_trust_mark
            state={Map.get(@program, :verification_state, :unverified)}
            variant={:compact}
          />
        </div>
        <div class="mt-2 flex items-center gap-2 text-[13px] text-[var(--fg-muted)] flex-wrap">
          <span :if={@program.age_range} class="flex items-center gap-1">
            <.icon name="hero-user" class="w-4 h-4" />
            {@program.age_range}
          </span>
          <span :if={@program.age_range && @program.period}>·</span>
          <span :if={@program.period}>{@program.period}</span>
        </div>
        <div class="mt-4 flex items-center justify-between pt-4 border-t border-[var(--border-light)]">
          <span class="text-sm text-[var(--fg-muted)] line-clamp-1">
            {@program.description}
          </span>
          <%!-- typography-lint-ignore: program-card "View →" callout in display font matches View All link --%>
          <span class="text-sm font-display font-bold text-[var(--brand-primary-dark)] shrink-0 ml-3">
            {gettext("View →")}
          </span>
        </div>
      </div>
    </.kh_card>
    """
  end

  defp format_price(price) when is_float(price), do: :erlang.float_to_binary(price, decimals: 0)
  defp format_price(price) when is_integer(price), do: Integer.to_string(price)
  defp format_price(price), do: to_string(price)

  defp schedule_label(%{meeting_days: [_ | _] = days}) do
    days
    |> Enum.take(2)
    |> Enum.map(&String.slice(to_string(&1), 0, 3))
    |> Enum.map_join(", ", &String.capitalize/1)
  end

  defp schedule_label(_), do: nil

  ## ---------------------------------------------------------------------------
  ## Features grid
  ## ---------------------------------------------------------------------------

  @doc """
  "Why Klass Hero" features grid. Cream background, pill label, three
  cards with gradient icon chips.

  Maps to bundle's `MkFeatures` (Sections.jsx:203). Reuses the existing
  gettext keys for the three backed cards (Safety First / Easy Scheduling /
  Community Focused) — copy is unchanged from the prior `home_live.ex`.
  """
  def mk_features(assigns) do
    ~H"""
    <section id="mk-features" class="py-16 lg:py-24 bg-hero-cream-100">
      <div class="max-w-7xl mx-auto px-6">
        <div class="text-center max-w-2xl mx-auto mb-14">
          <.kh_pill tone={:primary} class="mb-3">{gettext("Why Klass Hero")}</.kh_pill>
          <%!-- typography-lint-ignore: marketing section title intentionally larger than Theme.typography(:page_title) --%>
          <h2 class="font-display font-bold tracking-tight text-4xl lg:text-5xl text-hero-black">
            {gettext("Everything parents need, nothing they don't")}
          </h2>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          <.kh_card class="p-7 hover:shadow-lg hover:-translate-y-1">
            <.kh_icon_chip icon="hero-shield-check" gradient={:cool} />
            <h3 class="mt-5 font-bold text-xl text-hero-black">{gettext("Safety First")}</h3>
            <p class="mt-2 text-[var(--fg-muted)] leading-relaxed">
              {gettext(
                "Every provider is rigorously vetted. We prioritize child safety above all else, giving parents peace of mind."
              )}
            </p>
          </.kh_card>

          <.kh_card class="p-7 hover:shadow-lg hover:-translate-y-1">
            <.kh_icon_chip icon="hero-calendar-days" gradient={:primary} />
            <h3 class="mt-5 font-bold text-xl text-hero-black">{gettext("Easy Scheduling")}</h3>
            <p class="mt-2 text-[var(--fg-muted)] leading-relaxed">
              {gettext(
                "Book camps, tutors, and workshops instantly. Our integrated planner helps you manage your child's busy life."
              )}
            </p>
          </.kh_card>

          <.kh_card class="p-7 hover:shadow-lg hover:-translate-y-1">
            <.kh_icon_chip icon="hero-user-group" gradient={:safety} />
            <h3 class="mt-5 font-bold text-xl text-hero-black">{gettext("Community Focused")}</h3>
            <p class="mt-2 text-[var(--fg-muted)] leading-relaxed">
              {gettext(
                "Built for the Berlin international community. Integrated secure encrypted messaging to connect with local families and trusted educators nearby."
              )}
            </p>
          </.kh_card>
        </div>
      </div>
    </section>
    """
  end

  ## ---------------------------------------------------------------------------
  ## Provider CTA (dark)
  ## ---------------------------------------------------------------------------

  @doc """
  Dark "For Providers" section with two blur orbs, headline, two CTAs, and
  three numbered step cards.

  Maps to bundle's `MkProviderCTA` (Sections.jsx:236). Copy preserves the
  existing gettext keys from the prior `home_live.ex` provider section.
  """
  def mk_provider_cta(assigns) do
    ~H"""
    <section
      id="mk-provider-cta"
      class="py-16 lg:py-24 bg-hero-black text-white relative overflow-hidden"
    >
      <div class="absolute -top-20 -right-20 w-96 h-96 rounded-full bg-hero-blue-500 opacity-20 blur-3xl pointer-events-none">
      </div>
      <div class="absolute -bottom-20 -left-20 w-96 h-96 rounded-full bg-hero-yellow-500 opacity-15 blur-3xl pointer-events-none">
      </div>

      <div class="relative max-w-7xl mx-auto px-6">
        <div class="grid lg:grid-cols-2 gap-12 items-center">
          <div>
            <.kh_pill tone={:accent} class="mb-4">{gettext("For Providers")}</.kh_pill>
            <%!-- typography-lint-ignore: marketing section title intentionally larger than Theme.typography(:page_title) --%>
            <h2 class="font-display font-bold tracking-tight text-4xl lg:text-5xl text-white">
              {gettext("How to Grow Your Youth Program")}
            </h2>
            <p class="text-white/70 text-lg mt-4 leading-relaxed">
              {gettext(
                "Join Berlin's trusted network of educators. We handle payments, scheduling, and discovery — you focus on teaching."
              )}
            </p>
            <p id="mk-provider-cta-subtitle" class="text-white/90 text-base font-semibold mt-6">
              {gettext("Are you an educator, coach, or artist?")}
            </p>
            <div class="mt-8 flex gap-3 flex-wrap">
              <.link navigate={~p"/for-providers"}>
                <.kh_button variant={:primary} size={:lg} id="mk-provider-cta-primary">
                  {gettext("Learn How to Become a Hero →")}
                </.kh_button>
              </.link>
              <.link navigate={~p"/for-providers"}>
                <.kh_button
                  variant={:ghost}
                  size={:lg}
                  class="!text-white !border-white/30 hover:!bg-white/10"
                >
                  {gettext("See provider plans")}
                </.kh_button>
              </.link>
            </div>
          </div>

          <div class="space-y-4">
            <.mk_provider_step
              number="01"
              title={gettext("List Your Program")}
              description={
                gettext(
                  "Set up your teaching profile and list your programs in minutes. Share your expertise with families who need it."
                )
              }
            />
            <.mk_provider_step
              number="02"
              title={gettext("Get Bookings")}
              description={
                gettext(
                  "Parents find you through Klass Hero. Approve or auto-accept bookings with secure messaging built in."
                )
              }
            />
            <.mk_provider_step
              number="03"
              title={gettext("Get Paid & Grow")}
              description={
                gettext(
                  "Secure weekly payouts. Insights into your business and opportunities to expand your impact."
                )
              }
            />
          </div>
        </div>
      </div>
    </section>
    """
  end

  attr :number, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true

  defp mk_provider_step(assigns) do
    ~H"""
    <div class="flex gap-5 p-5 bg-white/5 backdrop-blur-sm rounded-2xl border border-white/10">
      <%!-- typography-lint-ignore: numbered-step badge uses display font for numeric callout --%>
      <div class="flex-shrink-0 w-14 h-14 rounded-xl bg-hero-yellow-500 text-black flex items-center justify-center font-display font-extrabold text-xl">
        {@number}
      </div>
      <div>
        <h4 class="font-bold text-lg">{@title}</h4>
        <p class="text-white/70 mt-1">{@description}</p>
      </div>
    </div>
    """
  end

  ## ---------------------------------------------------------------------------
  ## Founder
  ## ---------------------------------------------------------------------------

  @doc """
  "Our Story" centered narrative block with primary CTA to /about.

  Maps to bundle's `MkFounder` (Sections.jsx:81).
  """
  def mk_founder(assigns) do
    ~H"""
    <section id="mk-founder" class="py-16 lg:py-24 bg-white">
      <div class="max-w-3xl mx-auto px-6 text-center">
        <.kh_pill tone={:outline} class="mb-4">{gettext("Our Story")}</.kh_pill>
        <%!-- typography-lint-ignore: marketing section title intentionally larger than Theme.typography(:page_title) --%>
        <h2 class="font-display font-extrabold tracking-tight text-4xl lg:text-5xl text-hero-black">
          {gettext("Built by Parents to Empower Educators.")}
        </h2>
        <p class="mt-6 text-lg leading-relaxed text-[var(--fg-muted)]">
          {gettext(
            "As fathers and partners of teachers in Berlin, we saw and heard firsthand how hard it is to find, book, and manage quality youth activities outside the classroom. Klass Hero is the complete platform connecting Berlin families and schools with trusted, vetted activity providers — offering safe, supervised, and enriching experiences across sports, arts, tutoring, and more. We verify every provider, structure every booking, and support every step — so parents know their child is in good hands, and providers can focus on what they do best: inspiring kids."
          )}
        </p>
        <div class="mt-8">
          <.link navigate={~p"/about"}>
            <.kh_button variant={:primary} size={:lg}>
              {gettext("Read our founding story →")}
            </.kh_button>
          </.link>
        </div>
      </div>
    </section>
    """
  end

  ## ---------------------------------------------------------------------------
  ## FAQ
  ## ---------------------------------------------------------------------------

  @doc """
  FAQ section wrapper. Pass `<.mk_faq_item>` children inside.

  Maps to bundle's `MkFAQ` (Sections.jsx:274). Uses native `<details>`
  elements so accordion open/close is purely client-side — no LV events.
  """
  attr :title, :string, default: nil
  attr :subtitle, :string, default: nil
  slot :inner_block, required: true

  def mk_faq(assigns) do
    ~H"""
    <section id="mk-faq" class="py-16 lg:py-24 bg-hero-cream-100">
      <div class="max-w-3xl mx-auto px-6">
        <div class="text-center mb-10">
          <.kh_pill tone={:outline} class="mb-3">{gettext("FAQ")}</.kh_pill>
          <%!-- typography-lint-ignore: marketing section title intentionally larger than Theme.typography(:page_title) --%>
          <h2 class="font-display font-bold tracking-tight text-4xl text-hero-black">
            {@title || gettext("Questions, answered.")}
          </h2>
          <p :if={@subtitle} class="mt-3 text-[var(--fg-muted)]">{@subtitle}</p>
        </div>

        <div class="space-y-3">
          {render_slot(@inner_block)}
        </div>
      </div>
    </section>
    """
  end

  @doc """
  Single FAQ row. Native `<details>` so open/close survives without LV
  state. Open state gets cream background + shadow + chevron rotation
  driven entirely by CSS via `[open]` selectors.
  """
  attr :id, :string, default: nil
  attr :question, :string, required: true
  slot :inner_block, required: true

  def mk_faq_item(assigns) do
    ~H"""
    <details
      id={@id}
      class="group bg-white open:bg-hero-cream-100 open:shadow-md border border-[var(--border-light)] rounded-xl overflow-hidden transition-all"
    >
      <summary class="cursor-pointer list-none w-full p-5 flex items-center justify-between text-left gap-4">
        <span class="font-bold text-hero-black">{@question}</span>
        <.icon
          name="hero-chevron-down"
          class="w-5 h-5 shrink-0 transition-transform group-open:rotate-180"
        />
      </summary>
      <div class="px-5 pb-5 text-[var(--fg-muted)] leading-relaxed">
        {render_slot(@inner_block)}
      </div>
    </details>
    """
  end

  ## ---------------------------------------------------------------------------
  ## Footer
  ## ---------------------------------------------------------------------------

  @doc """
  Dark marketing footer with per-page CTA block (mobile), 4-column nav
  (desktop), and a mobile-only legal-link row pinned above the © line.
  Desktop relies on the Company column for legal links.

  Maps to bundle's `MkFooter` (Sections.jsx:305).
  """
  attr :active, :atom, default: :home

  def mk_footer(assigns) do
    assigns = assign(assigns, cta: footer_cta(assigns.active))

    ~H"""
    <footer class="bg-hero-black text-white">
      <div class="md:hidden">
        <div class="px-6 py-12 border-b border-white/10">
          <.kh_logo size={36} />
          <%!-- typography-lint-ignore: marketing footer CTA headline in display font --%>
          <h3 class="mt-5 font-display font-extrabold tracking-tight text-2xl leading-tight">
            {@cta.headline}
          </h3>
          <div class="mt-5 flex flex-col gap-2.5">
            <.link navigate={@cta.primary_href}>
              <.kh_button variant={:primary} size={:md} class="!w-full">
                {@cta.primary_label}
              </.kh_button>
            </.link>
            <.link navigate={@cta.secondary_href}>
              <.kh_button
                variant={:ghost}
                size={:md}
                class="!w-full !text-white !border-white/30 hover:!bg-white/10"
              >
                {@cta.secondary_label}
              </.kh_button>
            </.link>
          </div>
        </div>

        <nav class="px-6 py-8 border-b border-white/10" aria-label={gettext("Footer mobile")}>
          <ul class="grid grid-cols-2 gap-x-4 gap-y-3.5 text-[15px] font-semibold">
            <li :for={{label, href} <- mobile_footer_links(@active)}>
              <.link navigate={href} class="text-white/80 hover:text-white block py-1">
                {label}
              </.link>
            </li>
          </ul>
        </nav>

        <div class="px-6 py-6 flex flex-col gap-3 text-xs text-white/50">
          <div class="flex flex-wrap gap-x-4 gap-y-1.5">
            <.link navigate={~p"/privacy"} class="hover:text-white">{gettext("Privacy")}</.link>
            <.link navigate={~p"/terms"} class="hover:text-white">{gettext("Terms")}</.link>
          </div>
          <div class="flex items-center justify-between">
            <span>© {DateTime.utc_now().year} Klass Hero · Berlin</span>
            <span class="flex items-center gap-1 px-2.5 py-1 rounded-full border border-white/20 text-white/80">
              <span>🇬🇧</span><span class="font-semibold">EN</span>
            </span>
          </div>
        </div>
      </div>

      <div class="hidden md:block py-14">
        <div class="max-w-7xl mx-auto px-6">
          <div class="grid lg:grid-cols-4 gap-10">
            <div>
              <.kh_logo size={36} />
              <p class="mt-4 text-white/60 text-sm leading-relaxed">
                {gettext(
                  "Berlin's network for trusted youth educators. Built by parents, for parents."
                )}
              </p>
            </div>

            <.mk_footer_column
              title={gettext("Families")}
              links={[
                {gettext("Browse Programs"), ~p"/programs"},
                {gettext("How it Works"), ~p"/"},
                {gettext("Trust & Safety"), ~p"/trust-safety"}
              ]}
            />

            <.mk_footer_column
              title={gettext("Providers")}
              links={[
                {gettext("Start Teaching"), ~p"/for-providers"},
                {gettext("Pricing"), ~p"/for-providers"},
                {gettext("Help Center"), ~p"/contact"}
              ]}
            />

            <.mk_footer_column
              title={gettext("Company")}
              links={[
                {gettext("About"), ~p"/about"},
                {gettext("Contact"), ~p"/contact"},
                {gettext("Privacy"), ~p"/privacy"},
                {gettext("Terms"), ~p"/terms"}
              ]}
            />
          </div>

          <div class="mt-10 pt-6 border-t border-white/10 text-sm text-white/50">
            © {DateTime.utc_now().year} Klass Hero · Berlin
          </div>
        </div>
      </div>
    </footer>
    """
  end

  attr :title, :string, required: true
  attr :links, :list, required: true

  defp mk_footer_column(assigns) do
    ~H"""
    <div>
      <h4 class="font-bold text-white mb-4">{@title}</h4>
      <ul class="space-y-2 text-white/60 text-sm">
        <li :for={{label, href} <- @links}>
          <.link navigate={href} class="hover:text-white transition-colors">{label}</.link>
        </li>
      </ul>
    </div>
    """
  end

  # Per-page footer CTA — don't ask users to do what they're already doing.
  defp footer_cta(:programs) do
    %{
      headline: gettext("Teaching kids is your thing? Join as a Hero."),
      primary_label: gettext("Become a Hero →"),
      primary_href: "/for-providers",
      secondary_label: gettext("Learn how vetting works"),
      secondary_href: "/trust-safety"
    }
  end

  defp footer_cta(:providers) do
    %{
      headline: gettext("Looking for programs for your child?"),
      primary_label: gettext("Browse Programs →"),
      primary_href: "/programs",
      secondary_label: gettext("How we vet providers"),
      secondary_href: "/trust-safety"
    }
  end

  defp footer_cta(:trust) do
    %{
      headline: gettext("Ready to find your child's next adventure?"),
      primary_label: gettext("Browse Programs →"),
      primary_href: "/programs",
      secondary_label: gettext("Talk to us"),
      secondary_href: "/contact"
    }
  end

  defp footer_cta(:contact) do
    %{
      headline: gettext("While you're here — explore programs."),
      primary_label: gettext("Browse Programs →"),
      primary_href: "/programs",
      secondary_label: gettext("Become a Hero"),
      secondary_href: "/for-providers"
    }
  end

  defp footer_cta(_) do
    %{
      headline: gettext("Ready to find your child's next adventure?"),
      primary_label: gettext("Browse Programs →"),
      primary_href: "/programs",
      secondary_label: gettext("Become a Hero"),
      secondary_href: "/for-providers"
    }
  end

  defp mobile_footer_links(active) do
    all = [
      {gettext("Browse Programs"), "/programs", :programs},
      {gettext("For Providers"), "/for-providers", :providers},
      {gettext("Trust & Safety"), "/trust-safety", :trust},
      {gettext("About"), "/about", :about},
      {gettext("Contact"), "/contact", :contact},
      {gettext("Help Center"), "/contact", nil}
    ]

    all
    |> Enum.reject(fn {_, _, key} -> key && key == active end)
    |> Enum.take(6)
    |> Enum.map(fn {label, href, _} -> {label, href} end)
  end

  ## ---------------------------------------------------------------------------
  ## Programs catalog (peach hero + filter pills + controls + list-mode row)
  ## ---------------------------------------------------------------------------

  @doc """
  Peach-gradient hero for the `/programs` catalog. Outline pill + headline
  with yellow `activities` highlight + subtitle + search form + 8 filter
  pills.

  Maps to bundle's `MkPrograms` page-header (Sections.jsx:899-946).

  Search and filter selection preserve the existing
  `phx-submit="search"` and `phx-click="filter_select"` events on
  `ProgramsLive`.
  """
  attr :search_query, :string, default: ""
  attr :active_filter, :string, default: "all"
  attr :filters, :list, required: true, doc: "list of %{id:, label:}"

  def mk_programs_hero(assigns) do
    ~H"""
    <section
      id="mk-programs-hero"
      class={[Theme.gradient(:base_fade), "relative overflow-hidden pt-14 pb-12 lg:pt-20 lg:pb-16"]}
    >
      <div class="absolute top-10 right-1/4 w-72 h-72 rounded-full bg-hero-yellow-500 opacity-20 blur-3xl pointer-events-none">
      </div>
      <div class="absolute bottom-0 left-1/4 w-72 h-72 rounded-full bg-hero-blue-400 opacity-15 blur-3xl pointer-events-none">
      </div>

      <div class="relative max-w-7xl mx-auto px-6 text-center">
        <.kh_pill tone={:outline} class="mb-5">{gettext("Explore Programs")}</.kh_pill>

        <%!-- typography-lint-ignore: marketing programs hero scales fluidly via clamp() --%>
        <h1 class="font-display font-extrabold tracking-tight text-[clamp(36px,5vw,60px)] leading-[1.05] text-hero-black">
          {gettext("Discover")}
          <span class="bg-hero-yellow-500 px-2 rounded-lg">{gettext("activities")}</span>
          {gettext(", camps & classes for your child")}
        </h1>

        <p class="mt-5 text-lg text-[var(--fg-muted-on-light)] max-w-2xl mx-auto">
          {gettext(
            "Hand-picked, vetted programs across Berlin — filter by category, age, or schedule."
          )}
        </p>

        <div class="mt-9 max-w-2xl mx-auto">
          <form id="mk-programs-search" phx-change="search" phx-submit="search">
            <div class="flex items-center gap-2 p-2 bg-white rounded-full shadow-lg border border-[var(--border-light)]">
              <div class="flex-1 relative">
                <div class="absolute left-4 top-1/2 -translate-y-1/2 text-[var(--fg-muted)]">
                  <.icon name="hero-magnifying-glass" class="w-5 h-5" />
                </div>
                <input
                  id="mk-programs-search-input"
                  type="text"
                  name="search"
                  value={@search_query}
                  phx-change="search"
                  phx-hook="Debounce"
                  data-debounce="200"
                  placeholder={gettext("Search programs, providers, neighborhoods...")}
                  class="w-full pl-11 pr-3 py-2.5 bg-transparent outline-none text-[15px] text-hero-black"
                />
              </div>
              <.kh_button type="submit" variant={:primary}>{gettext("Search")}</.kh_button>
            </div>
          </form>
        </div>

        <div class="mt-7 flex items-center justify-center gap-2 flex-wrap" id="mk-programs-filters">
          <button
            :for={filter <- @filters}
            type="button"
            phx-click="filter_select"
            phx-value-filter={filter.id}
            data-filter={filter.id}
            data-active={if @active_filter == filter.id, do: "true", else: "false"}
            class={[
              "px-4 py-2 rounded-full text-sm font-semibold transition-all border-2 cursor-pointer",
              if(@active_filter == filter.id,
                do: "bg-[var(--brand-primary)] border-[var(--brand-primary)] text-black shadow-sm",
                else:
                  "bg-white border-[var(--border-light)] text-[var(--fg-body)] hover:border-[var(--brand-primary)]"
              )
            ]}
          >
            {filter.label}
          </button>
        </div>
      </div>
    </section>
    """
  end

  @doc """
  Result-count summary + sort dropdown + grid/list toggle row.

  Maps to bundle's `MkPrograms` controls (Sections.jsx:951-989). The sort
  dropdown is implemented as a native `<details>` so the open/close state
  is purely client-side (same pattern as `mk_faq`).
  """
  attr :count, :integer, required: true
  attr :search_query, :string, default: ""
  attr :active_filter, :string, default: "all"
  attr :filters, :list, required: true
  attr :sort, :string, default: "recommended"
  attr :view_mode, :atom, default: :grid, values: [:grid, :list]

  def mk_programs_controls(assigns) do
    assigns = assign(assigns, sort_options: sort_options())

    ~H"""
    <div class="flex items-center justify-between gap-3 py-6 flex-wrap border-b border-[var(--border-light)]">
      <div class="text-sm text-[var(--fg-muted)]">
        <%!-- typography-lint-ignore: result-count uses display font as numeric callout --%>
        <span class="font-display font-bold text-hero-black text-base">{@count}</span>
        <span>{ngettext("program", "programs", @count)}</span>
        <%= if active_filter_label = active_filter_label(@filters, @active_filter) do %>
          <span>{gettext("in")}</span>
          <span class="font-semibold text-hero-black">{active_filter_label}</span>
        <% end %>
        <%= if @search_query != "" do %>
          <span>{gettext("matching")}</span>
          <span class="font-semibold text-hero-black">"{@search_query}"</span>
        <% end %>
      </div>

      <div class="flex items-center gap-3">
        <details id="mk-sort-dropdown" class="relative group">
          <summary class="list-none cursor-pointer flex items-center gap-2 px-4 py-2 rounded-lg border border-[var(--border-light)] bg-white hover:border-[var(--brand-primary)] text-sm font-semibold">
            <span class="text-[var(--fg-muted)]">{gettext("Sort:")}</span>
            <span>{sort_label(@sort)}</span>
            <.icon
              name="hero-chevron-down"
              class="w-4 h-4 transition-transform group-open:rotate-180"
            />
          </summary>
          <div class="absolute right-0 mt-2 w-56 bg-white rounded-xl border border-[var(--border-light)] shadow-lg overflow-hidden z-20">
            <button
              :for={{key, label} <- @sort_options}
              type="button"
              phx-click={
                JS.push("sort_select", value: %{sort: key})
                |> JS.remove_attribute("open", to: "#mk-sort-dropdown")
              }
              data-sort={key}
              class={[
                "w-full text-left px-4 py-2.5 text-sm font-semibold cursor-pointer hover:bg-[var(--hero-cream-100)]",
                if(@sort == key,
                  do: "bg-[var(--hero-cream-100)] text-[var(--brand-primary-dark)]",
                  else: "text-[var(--fg-body)]"
                )
              ]}
            >
              {label}
            </button>
          </div>
        </details>

        <div
          id="mk-view-toggle"
          class="flex items-center bg-[var(--hero-cream-100)] rounded-lg p-1"
        >
          <button
            type="button"
            phx-click="toggle_view"
            phx-value-view="grid"
            data-view="grid"
            data-active={if @view_mode == :grid, do: "true", else: "false"}
            class={[
              "px-3 py-1.5 rounded-md text-sm font-semibold cursor-pointer transition-colors",
              if(@view_mode == :grid,
                do: "bg-white shadow-sm text-hero-black",
                else: "text-[var(--fg-muted)]"
              )
            ]}
          >
            {gettext("Grid")}
          </button>
          <button
            type="button"
            phx-click="toggle_view"
            phx-value-view="list"
            data-view="list"
            data-active={if @view_mode == :list, do: "true", else: "false"}
            class={[
              "px-3 py-1.5 rounded-md text-sm font-semibold cursor-pointer transition-colors",
              if(@view_mode == :list,
                do: "bg-white shadow-sm text-hero-black",
                else: "text-[var(--fg-muted)]"
              )
            ]}
          >
            {gettext("List")}
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp sort_options do
    [
      {"recommended", gettext("Recommended")},
      {"newest", gettext("Newest")},
      {"price_low", gettext("Price: low to high")},
      {"price_high", gettext("Price: high to low")}
    ]
  end

  defp sort_label(key) do
    sort_options()
    |> List.keyfind(key, 0)
    |> case do
      {_, label} -> label
      _ -> gettext("Recommended")
    end
  end

  defp active_filter_label(_filters, "all"), do: nil

  defp active_filter_label(filters, active) do
    case Enum.find(filters, &(&1.id == active)) do
      %{label: label} -> label
      _ -> nil
    end
  end

  @doc """
  Horizontal list-mode row for the catalog list view. Built on the
  `kh_list_row` primitive.
  """
  attr :id, :string, required: true
  attr :program, :map, required: true

  def mk_program_list_row(assigns) do
    ~H"""
    <.kh_card
      id={@id}
      data-program-id={@program.id}
      phx-click="program_click"
      phx-value-program-id={@program.id}
      class="p-5 hover:shadow-md cursor-pointer flex flex-col md:flex-row gap-5"
    >
      <div class={[
        "md:w-56 h-32 md:h-auto rounded-xl shrink-0 relative overflow-hidden",
        !@program.cover_image_url && @program.gradient_class
      ]}>
        <img
          :if={@program.cover_image_url}
          src={@program.cover_image_url}
          alt={@program.title}
          loading="lazy"
          class="absolute inset-0 w-full h-full object-cover"
        />
        <div
          :if={!@program.cover_image_url}
          class="absolute inset-0 flex items-center justify-center"
        >
          <.icon name={@program.icon_name} class="w-10 h-10 text-white/80" />
        </div>
      </div>

      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-2 mb-2 flex-wrap">
          <.kh_pill tone={:dark}>{@program.category}</.kh_pill>
          <.kh_pill :if={@program.age_range} tone={:outline}>{@program.age_range}</.kh_pill>
        </div>
        <h3 class="font-bold text-xl leading-snug text-hero-black">{@program.title}</h3>
        <p
          :if={@program.description}
          class="mt-1 text-sm text-[var(--fg-muted)] line-clamp-2"
        >
          {@program.description}
        </p>
        <div class="mt-3 flex items-center gap-3 text-sm text-[var(--fg-muted)] flex-wrap">
          <span :if={schedule_label(@program)} class="flex items-center gap-1.5">
            <.icon name="hero-clock" class="w-4 h-4" />
            {schedule_label(@program)}
          </span>
          <span :if={@program.price}>
            <span class="font-semibold text-hero-black">€{format_price(@program.price)}</span>
            <span :if={@program.period}>{" "}{@program.period}</span>
          </span>
        </div>
      </div>

      <div class="flex items-center justify-end md:justify-center">
        <%!-- typography-lint-ignore: marketing accent link uses display font for visual emphasis --%>
        <span class="font-display font-bold text-[var(--brand-primary-dark)] flex items-center gap-1">
          {gettext("View")}
          <.icon name="hero-arrow-right" class="w-4 h-4" />
        </span>
      </div>
    </.kh_card>
    """
  end

  @doc """
  Generic empty state with circular icon chip + title + description and
  optional `Clear filters` CTA. Used by the catalog when the search/filter
  yields no results.
  """
  attr :icon, :string, default: "hero-magnifying-glass"
  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :clear_event, :string, default: nil, doc: "phx-click event for the clear-filters CTA"
  attr :clear_label, :string, default: nil

  def mk_empty_state(assigns) do
    ~H"""
    <div id="mk-empty" data-testid="empty-state" class="text-center py-20">
      <div class="w-20 h-20 mx-auto rounded-full bg-[var(--hero-cream-100)] flex items-center justify-center mb-5">
        <.icon name={@icon} class="w-9 h-9 text-[var(--fg-muted)]" />
      </div>
      <%!-- typography-lint-ignore: marketing empty-state title uses display font --%>
      <h3 class="font-display font-bold text-2xl text-hero-black">{@title}</h3>
      <p :if={@description} class="mt-2 text-[var(--fg-muted)] max-w-md mx-auto">
        {@description}
      </p>
      <div :if={@clear_event} class="mt-6">
        <button type="button" phx-click={@clear_event}>
          <.kh_button variant={:primary}>
            {@clear_label || gettext("Clear filters")}
          </.kh_button>
        </button>
      </div>
    </div>
    """
  end

  ## ---------------------------------------------------------------------------
  ## Generic page primitives (shared across Trust & Safety, About, Contact)
  ## ---------------------------------------------------------------------------

  @doc """
  Generic peach-gradient page hero used by Trust & Safety, About, and Contact.

  Maps to bundle's `MkPageHero` (Sections.jsx:426). The H1 is rendered through
  the `:title` slot so callers can wrap a span in
  `bg-hero-yellow-500 px-2 rounded-lg` to highlight a word.
  """
  attr :id, :string, default: "mk-page-hero"
  attr :eyebrow_icon, :string, default: nil, doc: "Heroicon name for kh_icon_chip eyebrow"

  attr :eyebrow_gradient, :atom,
    default: :primary,
    values: [:primary, :comic, :cool, :art, :safety, :dark, :yellow, :pink, :mixed]

  attr :pill, :string, default: nil, doc: "Optional outline pill text rendered above the title"
  slot :title, required: true
  slot :lede

  def mk_page_hero(assigns) do
    ~H"""
    <section
      id={@id}
      class={[Theme.gradient(:base_fade), "relative overflow-hidden pt-16 pb-20 lg:pt-24 lg:pb-28"]}
    >
      <div class="absolute top-10 right-1/4 w-72 h-72 rounded-full bg-hero-yellow-500 opacity-20 blur-3xl pointer-events-none">
      </div>
      <div class="absolute bottom-0 left-1/4 w-72 h-72 rounded-full bg-hero-blue-400 opacity-15 blur-3xl pointer-events-none">
      </div>

      <div class="relative max-w-5xl mx-auto px-6 text-center">
        <div :if={@eyebrow_icon} class="flex justify-center mb-6">
          <.kh_icon_chip icon={@eyebrow_icon} gradient={@eyebrow_gradient} size={:lg} />
        </div>
        <.kh_pill :if={@pill} tone={:outline} class="mb-5">{@pill}</.kh_pill>

        <%!-- typography-lint-ignore: marketing page hero scales fluidly via clamp() --%>
        <h1 class="font-display font-extrabold tracking-tight text-[clamp(40px,6vw,72px)] leading-[1.02] text-hero-black">
          {render_slot(@title)}
        </h1>
        <p
          :if={@lede != []}
          class="mt-6 text-lg md:text-xl text-[var(--fg-muted-on-light)] max-w-3xl mx-auto leading-relaxed"
        >
          {render_slot(@lede)}
        </p>
      </div>
    </section>
    """
  end

  @doc """
  Generic peach CTA closer used by Trust & Safety (and reusable by About /
  Contact follow-ups). H2 + lede + primary CTA via slot, with an optional
  tagline + sub-tagline rendered below a horizontal rule.
  """
  attr :id, :string, default: "mk-cta"
  attr :title, :string, required: true
  attr :lede, :string, default: nil
  attr :tagline, :string, default: nil
  attr :sub_tagline, :string, default: nil
  slot :cta, required: true

  def mk_cta_section(assigns) do
    ~H"""
    <section id={@id} class={[Theme.gradient(:base_fade), "py-16 lg:py-20 text-center"]}>
      <div class="max-w-3xl mx-auto px-6">
        <%!-- typography-lint-ignore: marketing CTA closer title intentionally larger than Theme.typography(:page_title) --%>
        <h2 class="font-display font-bold tracking-tight text-4xl lg:text-5xl text-hero-black">
          {@title}
        </h2>
        <p :if={@lede} class="text-lg text-[var(--fg-muted-on-light)] mt-4">{@lede}</p>
        <div class="mt-8">
          {render_slot(@cta)}
        </div>

        <div :if={@tagline} class="mt-14 pt-10 border-t border-[var(--border-light)]">
          <%!-- typography-lint-ignore: display-font tagline is an intentional non-heading brand callout --%>
          <p class="font-display font-bold text-2xl tracking-tight text-hero-black">
            {@tagline}
          </p>
          <p :if={@sub_tagline} class="text-xl text-[var(--brand-primary-dark)] font-bold mt-2">
            {@sub_tagline}
          </p>
        </div>
      </div>
    </section>
    """
  end

  ## ---------------------------------------------------------------------------
  ## Trust & Safety section helpers
  ## ---------------------------------------------------------------------------

  @doc """
  Two-column commitment-and-vetted-card section. Maps to MkTrustSafety's
  first content block (Sections.jsx:746).
  """
  attr :title, :string, required: true
  attr :lede, :string, required: true
  attr :commitments, :list, required: true, doc: "list of strings"
  attr :vetted_title, :string, required: true
  attr :vetted_lede, :string, required: true
  attr :stats, :list, default: []

  def mk_trust_commitment(assigns) do
    ~H"""
    <section id="mk-trust-commitment" class="py-16 lg:py-24 bg-white">
      <div class="max-w-7xl mx-auto px-6 grid md:grid-cols-2 gap-12 items-center">
        <div class="space-y-6">
          <.kh_pill tone={:primary}>{gettext("Our Commitment")}</.kh_pill>
          <%!-- typography-lint-ignore: marketing section title intentionally larger than Theme.typography(:page_title) --%>
          <h2 class="font-display font-bold tracking-tight text-4xl lg:text-5xl text-hero-black">
            {@title}
          </h2>
          <p class="text-lg text-[var(--fg-muted)] leading-relaxed">{@lede}</p>
          <div class="space-y-3 pt-2">
            <div
              :for={commitment <- @commitments}
              class="flex items-center gap-3 bg-white p-4 rounded-xl border-2 border-hero-yellow-400"
            >
              <.icon
                name="hero-check-circle"
                class="w-5 h-5 text-[var(--brand-primary-dark)] flex-shrink-0"
              />
              <span class="font-bold text-hero-black">{commitment}</span>
            </div>
          </div>
        </div>

        <div class="bg-gradient-to-br from-[var(--brand-primary-dark)] to-hero-blue-700 rounded-3xl p-8 lg:p-10 text-white relative overflow-hidden min-h-[420px] flex flex-col">
          <.kh_pill tone={:accent} class="self-start">{gettext("Vetted with Care")}</.kh_pill>
          <%!-- typography-lint-ignore: marketing section title in display font on dark surface --%>
          <h3 class="mt-5 font-display font-bold tracking-tight text-3xl lg:text-4xl">
            {@vetted_title}
          </h3>
          <p class="mt-5 text-white/90 text-lg leading-relaxed">{@vetted_lede}</p>
          <div class="h-1 w-20 bg-hero-yellow-500 mt-6"></div>
          <div :if={@stats != []} class="mt-auto pt-6 grid grid-cols-3 gap-3">
            <div :for={{value, label} <- @stats}>
              <%!-- typography-lint-ignore: vetted-card stat value is a numeric/keyword display callout --%>
              <div class="font-display font-extrabold text-2xl text-hero-yellow-500">
                {value}
              </div>
              <div :if={label} class="text-xs text-white/70 uppercase tracking-wider">
                {label}
              </div>
            </div>
          </div>
          <.icon
            name="hero-shield-check"
            class="w-48 h-48 text-white/10 absolute -bottom-6 -right-6 pointer-events-none"
          />
        </div>
      </div>
    </section>
    """
  end

  @doc """
  The canonical 6-step provider vetting list, shared by the `/about`
  (`mk_about_vetting/1`) and `/trust-safety` (`mk_trust_verification/1`) pages.

  Single source of truth for the static marketing copy — edit here once and both
  public pages update. Each step is `%{icon:, title:, description:}`. Distinct from
  the `verification_steps` DB table and `VettingChecklistPresenter`, which model
  per-provider onboarding state.
  """
  def vetting_steps do
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

  @doc """
  6-step verification grid. Maps to MkTrustSafety's verification block
  (Sections.jsx:784). Each step is `%{icon:, title:, description:}`.
  """
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :steps, :list, required: true

  def mk_trust_verification(assigns) do
    ~H"""
    <section id="mk-trust-verification" class="py-16 lg:py-24 bg-hero-cream-100">
      <div class="max-w-7xl mx-auto px-6">
        <div class="text-center max-w-2xl mx-auto mb-14">
          <.kh_pill tone={:accent} class="mb-3">{gettext("How We Verify Providers")}</.kh_pill>
          <%!-- typography-lint-ignore: marketing section title intentionally larger than Theme.typography(:page_title) --%>
          <h2 class="font-display font-bold tracking-tight text-4xl lg:text-5xl text-hero-black">
            {@title}
          </h2>
          <p :if={@subtitle} class="text-[var(--fg-muted)] text-lg mt-3">{@subtitle}</p>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
          <.kh_card
            :for={{step, idx} <- Enum.with_index(@steps, 1)}
            class="p-7 hover:shadow-lg hover:-translate-y-1 relative"
          >
            <div class="flex items-center gap-3 mb-4">
              <%!-- typography-lint-ignore: numbered step badge uses display font for numeric callout --%>
              <div class="w-9 h-9 rounded-full bg-hero-yellow-500 text-black font-display font-extrabold flex items-center justify-center">
                {idx}
              </div>
              <.kh_icon_chip icon={step.icon} gradient={:primary} size={:sm} />
            </div>
            <h3 class="font-bold text-xl text-hero-black">{step.title}</h3>
            <p class="mt-2 text-[var(--fg-muted)] leading-relaxed">{step.description}</p>
          </.kh_card>
        </div>
      </div>
    </section>
    """
  end

  @doc """
  Dark "ongoing quality" slab. Maps to MkTrustSafety's accountability block
  (Sections.jsx:807).
  """
  attr :title, :string, required: true
  attr :lede, :string, required: true
  attr :items, :list, required: true, doc: "list of strings"
  attr :warning, :string, default: nil

  def mk_trust_accountability(assigns) do
    ~H"""
    <section id="mk-trust-accountability" class="py-16 lg:py-24 bg-white">
      <div class="max-w-5xl mx-auto px-6">
        <div class="bg-hero-black rounded-3xl p-8 md:p-12 text-white relative overflow-hidden">
          <div class="absolute -top-20 -right-20 w-72 h-72 rounded-full bg-hero-blue-500 opacity-10 blur-3xl pointer-events-none">
          </div>
          <div class="absolute -bottom-20 -left-20 w-72 h-72 rounded-full bg-hero-yellow-500 opacity-10 blur-3xl pointer-events-none">
          </div>
          <div class="relative">
            <.kh_pill tone={:accent} class="mb-4">{gettext("Ongoing Quality")}</.kh_pill>
            <%!-- typography-lint-ignore: accountability slab title in display font on dark surface --%>
            <h2 class="font-display font-bold tracking-tight text-3xl lg:text-4xl text-hero-yellow-500">
              {@title}
            </h2>
            <p class="text-white/70 mt-5 text-lg leading-relaxed">{@lede}</p>

            <ul class="mt-8 space-y-4">
              <li
                :for={{item, idx} <- Enum.with_index(@items, 1)}
                class="flex items-start gap-4"
              >
                <%!-- typography-lint-ignore: numbered list badge uses display font for numeric callout --%>
                <div class="w-7 h-7 rounded-full bg-hero-yellow-500 text-black flex-shrink-0 flex items-center justify-center font-display font-extrabold text-sm mt-0.5">
                  {idx}
                </div>
                <span class="text-lg leading-snug">{item}</span>
              </li>
            </ul>

            <p
              :if={@warning}
              class="mt-10 text-white/60 italic border-l-4 border-hero-yellow-500 pl-5 leading-relaxed"
            >
              {@warning}
            </p>
          </div>
        </div>
      </div>
    </section>
    """
  end

  ## ---------------------------------------------------------------------------
  ## About page sections
  ## ---------------------------------------------------------------------------

  @doc """
  "Built for Berlin" 2-col block. Left: pill + headline + paragraphs + pull
  quote. Right: 3 yellow-bordered value cards. Maps to MkAbout's first
  content section (Sections.jsx:475).
  """
  attr :pill, :string, required: true
  attr :title, :string, required: true
  attr :paragraphs, :list, required: true, doc: "list of plain-text paragraphs"
  attr :quote, :string, default: nil, doc: "yellow-bordered pull-quote at the bottom of the column"
  attr :values, :list, required: true, doc: "list of %{icon:, title:, description:}"

  def mk_about_values(assigns) do
    ~H"""
    <section id="mk-about-values" class="py-16 lg:py-24 bg-white">
      <div class="max-w-7xl mx-auto px-6 grid md:grid-cols-2 gap-12 items-start">
        <div class="space-y-6">
          <.kh_pill tone={:primary}>{@pill}</.kh_pill>
          <%!-- typography-lint-ignore: marketing section title intentionally larger than Theme.typography(:page_title) --%>
          <h2 class="font-display font-bold tracking-tight text-4xl lg:text-5xl text-hero-black">
            {@title}
          </h2>
          <p :for={paragraph <- @paragraphs} class="text-lg text-[var(--fg-muted)] leading-relaxed">
            {paragraph}
          </p>
          <p
            :if={@quote}
            class="text-lg text-hero-black leading-relaxed font-semibold border-l-4 border-hero-yellow-500 pl-5"
          >
            {@quote}
          </p>
        </div>

        <div class="space-y-4">
          <.kh_card
            :for={value <- @values}
            class="p-6 border-2 border-hero-yellow-400 hover:shadow-lg"
          >
            <div class="flex items-start gap-5">
              <.kh_icon_chip icon={value.icon} gradient={:primary} />
              <div>
                <h3 class="font-bold text-lg text-hero-black">{value.title}</h3>
                <p class="text-[var(--fg-muted)] mt-1">{value.description}</p>
              </div>
            </div>
          </.kh_card>
        </div>
      </div>
    </section>
    """
  end

  @doc """
  6-step vetting grid with watermark digits. Maps to MkAbout's vetting
  block (Sections.jsx:507). Distinct from `mk_trust_verification` —
  About uses giant cream-coloured digits bleeding into the corner; Trust
  & Safety uses small numbered yellow circles next to the icon chip.
  """
  attr :pill, :string, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :steps, :list, required: true, doc: "list of %{icon:, title:, description:}"

  def mk_about_vetting(assigns) do
    ~H"""
    <section id="mk-about-vetting" class="py-16 lg:py-24 bg-hero-cream-100">
      <div class="max-w-7xl mx-auto px-6">
        <div class="text-center max-w-2xl mx-auto mb-14">
          <.kh_pill tone={:accent} class="mb-3">{@pill}</.kh_pill>
          <%!-- typography-lint-ignore: marketing section title intentionally larger than Theme.typography(:page_title) --%>
          <h2 class="font-display font-bold tracking-tight text-4xl lg:text-5xl text-hero-black">
            {@title}
          </h2>
          <p :if={@subtitle} class="text-[var(--fg-muted)] text-lg mt-3">{@subtitle}</p>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
          <.kh_card
            :for={{step, idx} <- Enum.with_index(@steps, 1)}
            class="p-7 hover:shadow-lg hover:-translate-y-1 relative overflow-hidden"
          >
            <%!-- typography-lint-ignore: vetting watermark digit is a display-font numeric callout --%>
            <div class="absolute -top-2 -right-2 font-display font-extrabold text-[120px] leading-none text-hero-cream-100 select-none pointer-events-none">
              {idx}
            </div>
            <div class="relative">
              <.kh_icon_chip icon={step.icon} gradient={:primary} />
              <h3 class="mt-5 font-bold text-xl text-hero-black">{step.title}</h3>
              <p class="mt-2 text-[var(--fg-muted)] leading-relaxed">{step.description}</p>
            </div>
          </.kh_card>
        </div>
      </div>
    </section>
    """
  end

  @doc """
  "Klass Hero Story" narrative + founders grid. Maps to MkAbout's story
  block (Sections.jsx:529). The narrative goes in the `:body` slot so
  callers can render `<strong>` highlights inline. Founders attr feeds
  the 4-up grid below.
  """
  attr :pill, :string, default: nil
  attr :title, :string, required: true
  attr :founders, :list, required: true, doc: "list of %{initials:, name:, role:, bio:}"
  slot :body, required: true

  def mk_about_story(assigns) do
    ~H"""
    <section id="mk-about-story" class="py-16 lg:py-24 bg-white">
      <div class="max-w-5xl mx-auto px-6">
        <div class="text-center mb-12">
          <.kh_pill :if={@pill} tone={:outline} class="mb-3">{@pill}</.kh_pill>
          <%!-- typography-lint-ignore: marketing section title intentionally larger than Theme.typography(:page_title) --%>
          <h2 class="font-display font-bold tracking-tight text-4xl lg:text-5xl text-hero-black">
            {@title}
          </h2>
        </div>

        <div class="prose prose-lg max-w-3xl mx-auto space-y-5 text-[var(--fg-muted)] leading-relaxed">
          {render_slot(@body)}
        </div>

        <div class="mt-14 grid grid-cols-2 md:grid-cols-4 gap-4">
          <.mk_founder_card :for={founder <- @founders} founder={founder} />
        </div>
      </div>
    </section>
    """
  end

  @doc """
  Single founder card: blue-gradient initials avatar, name, role label
  (uppercase tracking-wider blue), and bio. Composed by `mk_about_story`
  but exposed for direct use too.
  """
  attr :founder, :map, required: true

  def mk_founder_card(assigns) do
    ~H"""
    <.kh_card class="p-5 text-center hover:shadow-lg hover:-translate-y-1">
      <%!-- typography-lint-ignore: founder avatar initials in display font --%>
      <div class="w-16 h-16 mx-auto rounded-full bg-gradient-to-br from-hero-blue-400 to-hero-blue-600 text-white font-display font-extrabold text-xl flex items-center justify-center">
        {@founder.initials}
      </div>
      <h4 class="mt-3 font-bold text-hero-black">{@founder.name}</h4>
      <div class="text-xs text-[var(--brand-primary-dark)] font-semibold uppercase tracking-wider mt-0.5">
        {@founder.role}
      </div>
      <p class="mt-3 text-sm text-[var(--fg-muted)] leading-relaxed">{@founder.bio}</p>
    </.kh_card>
    """
  end

  ## ---------------------------------------------------------------------------
  ## Contact page primitives (form input + method row)
  ## ---------------------------------------------------------------------------

  @doc """
  Marketing-styled labeled input. Mirrors the handoff's `kh-input` look:
  rounded-xl, 1.5px border, focus ring at brand-primary. Takes the same
  `:field` attr as `<.input>` from CoreComponents so the existing form +
  changeset flow continues to work.

  Supports `:text`, `:email`, `:select`, `:textarea` types. Renders
  label with required-asterisk when `required` is set. Inline error
  feedback below the input.
  """
  attr :field, FormField, required: true
  attr :type, :string, default: "text", values: ~w(text email password select textarea)
  attr :label, :string, required: true
  attr :placeholder, :string, default: nil
  attr :required, :boolean, default: false
  attr :readonly, :boolean, default: false
  attr :autocomplete, :string, default: nil
  attr :rows, :integer, default: 5
  attr :options, :list, default: []
  attr :prompt, :string, default: nil

  def mk_input(assigns) do
    ~H"""
    <label class="block">
      <span class={[
        "text-sm font-semibold text-hero-black",
        @required && "after:content-['*'] after:ml-0.5 after:text-[var(--brand-primary-dark)]"
      ]}>
        {@label}
      </span>
      <div class="mt-1.5">
        <%= case @type do %>
          <% "select" -> %>
            <select
              id={@field.id}
              name={@field.name}
              autocomplete={@autocomplete}
              class={[mk_input_classes(), "appearance-none bg-white"]}
            >
              <option :if={@prompt} value="" disabled selected={@field.value in [nil, ""]}>
                {@prompt}
              </option>
              <option
                :for={{label, value} <- @options}
                value={value}
                selected={to_string(@field.value) == to_string(value)}
              >
                {label}
              </option>
            </select>
          <% "textarea" -> %>
            <textarea
              id={@field.id}
              name={@field.name}
              rows={@rows}
              placeholder={@placeholder}
              autocomplete={@autocomplete}
              readonly={@readonly}
              class={[mk_input_classes(), "resize-y"]}
            >{Phoenix.HTML.Form.normalize_value("textarea", @field.value)}</textarea>
          <% _ -> %>
            <input
              id={@field.id}
              type={@type}
              name={@field.name}
              value={Phoenix.HTML.Form.normalize_value(@type, @field.value)}
              placeholder={@placeholder}
              autocomplete={@autocomplete}
              readonly={@readonly}
              class={[mk_input_classes(), @readonly && "bg-[var(--hero-grey-100)] cursor-not-allowed"]}
            />
        <% end %>
      </div>
      <p
        :for={msg <- mk_input_errors(@field)}
        class="mt-1.5 text-sm text-[var(--error)] flex items-center gap-1"
      >
        <.icon name="hero-exclamation-circle-mini" class="w-4 h-4" />
        {msg}
      </p>
    </label>
    """
  end

  defp mk_input_classes do
    "w-full px-3.5 py-3 rounded-xl border-[1.5px] border-[var(--border-light)] bg-white text-[15px] text-hero-black placeholder:text-[var(--fg-muted)] transition-colors focus:outline-none focus:border-[var(--brand-primary)] focus:ring-4 focus:ring-[rgba(0,212,255,.12)]"
  end

  defp mk_input_errors(%FormField{errors: errors} = field) do
    if Phoenix.Component.used_input?(field), do: Enum.map(errors, &translate_error/1), else: []
  end

  defp translate_error({msg, opts}) do
    Gettext.dngettext(KlassHeroWeb.Gettext, "errors", msg, msg, opts[:count] || 1, opts)
  end

  @doc """
  Single contact-method row: yellow-bordered card with `:sm` icon chip,
  title, value, and optional note. Used 3× in ContactLive.
  """
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :value, :string, required: true
  attr :note, :string, default: nil

  def mk_method_row(assigns) do
    ~H"""
    <div class="flex items-start gap-4 p-4 rounded-xl border-2 border-hero-yellow-400 bg-white">
      <.kh_icon_chip icon={@icon} gradient={:primary} size={:sm} />
      <div class="min-w-0">
        <div class="font-semibold text-hero-black">{@title}</div>
        <div class="text-sm text-[var(--fg-muted)] truncate">{@value}</div>
        <div :if={@note} class="text-xs text-[var(--fg-muted)] opacity-80 mt-0.5">{@note}</div>
      </div>
    </div>
    """
  end
end
