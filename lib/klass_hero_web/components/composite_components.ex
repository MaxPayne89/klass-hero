defmodule KlassHeroWeb.CompositeComponents do
  @moduledoc """
  Provides composite UI components for Klass Hero application.

  This module contains larger, more complex components that compose together
  atomic components from UIComponents to create cohesive interface elements.
  """
  use Phoenix.Component
  use Gettext, backend: KlassHeroWeb.Gettext

  use Phoenix.VerifiedRoutes,
    endpoint: KlassHeroWeb.Endpoint,
    router: KlassHeroWeb.Router,
    statics: KlassHeroWeb.static_paths()

  import KlassHeroWeb.MarketingComponents, only: [mk_page_hero: 1, mk_cta_section: 1]
  import KlassHeroWeb.UIComponents
  import Phoenix.HTML, only: [raw: 1]

  alias KlassHeroWeb.Theme

  @doc """
  Renders a child profile card with progress and activities.

  ## Examples

      <.child_card
        name="Emma Johnson"
        age={8}
        school="Greenwood Elementary"
        sessions="8/10"
        progress={80}
        activities={["Art", "Chess", "Swimming"]}
      />
  """
  attr :name, :string, required: true
  attr :age, :integer, required: true
  attr :school, :string, required: true
  attr :sessions, :string, required: true, doc: "Format: '8/10'"
  attr :progress, :integer, required: true, doc: "Progress percentage (0-100)"
  attr :activities, :list, required: true, doc: "List of activity names"
  attr :class, :string, default: ""
  attr :rest, :global, include: ~w(phx-click phx-value-*)

  def child_card(assigns) do
    ~H"""
    <.card padding="p-4" class={"hover:shadow-md #{Theme.transition(:normal)} #{@class}"} {@rest}>
      <:body>
        <div class="flex items-start justify-between mb-3">
          <div class="flex-1">
            <h4 class={[Theme.typography(:card_title), "text-hero-black"]}>{@name}</h4>
            <p class="text-sm text-[var(--fg-muted)]">{@age} years old • {@school}</p>
          </div>
          <div class="text-right">
            <div class="text-sm font-medium text-hero-black">{@sessions}</div>
            <div class="text-xs text-[var(--fg-muted)]">{gettext("Sessions")}</div>
          </div>
        </div>
        <.progress_bar label={gettext("Progress")} percentage={@progress} class="mb-3" />
        <div class="flex flex-wrap gap-1">
          <.status_pill
            :for={activity <- @activities}
            color="custom"
            class="bg-hero-grey-100 text-hero-black-100"
          >
            {activity}
          </.status_pill>
        </div>
      </:body>
    </.card>
    """
  end

  @doc """
  Renders a child profile card for horizontal scrolling display with circular avatar.

  ## Examples

      <.child_profile_card
        child=%{name: "Leo", age: 10, initials: "L"}
      />
  """
  attr :child, :map, required: true
  attr :class, :string, default: nil

  def child_profile_card(assigns) do
    ~H"""
    <div class={["flex-shrink-0 w-64 snap-start", @class]}>
      <.card padding="p-4" class="hover:shadow-md transition-all">
        <:body>
          <div class="flex items-center gap-3">
            <div class={[
              "w-16 h-16 rounded-full flex items-center justify-center text-white font-bold text-2xl",
              Theme.gradient(:primary)
            ]}>
              {@child.initials}
            </div>
            <div class="flex-1 min-w-0">
              <h4 class={[Theme.typography(:card_title), "text-hero-black truncate"]}>
                {@child.name} ({@child.age})
              </h4>
            </div>
          </div>
        </:body>
      </.card>
    </div>
    """
  end

  @doc """
  Renders a weekly activity goal card with gradient background and progress bar.

  ## Examples

      <.weekly_goal_card
        goal=%{
          current: 4,
          target: 5,
          percentage: 80,
          message: "You're doing great! Just 1 more activity to reach your goal!"
        }
      />
  """
  attr :goal, :map, required: true
  attr :class, :string, default: nil

  def weekly_goal_card(assigns) do
    ~H"""
    <div class={[
      "w-full max-w-2xl mx-auto p-6",
      "bg-hero-blue-600",
      Theme.rounded(:xl),
      "shadow-lg",
      @class
    ]}>
      <div class="flex items-center gap-2 mb-4">
        <.icon name="hero-trophy-mini" class="w-6 h-6 text-white" />
        <h2 class="text-xl font-semibold text-white">
          {gettext("Weekly Activity Goal")}
        </h2>
      </div>

      <div class="text-center mb-4">
        <div class="text-6xl font-bold text-white mb-2">
          {@goal.percentage}%
        </div>
        <p class="text-white/90 text-sm">
          {@goal.current} / {@goal.target} {gettext("activities completed")}
        </p>
      </div>

      <div class="w-full bg-white/30 rounded-full h-3 mb-4">
        <div
          class="bg-white h-3 rounded-full transition-all duration-300"
          style={"width: #{@goal.percentage}%"}
        >
        </div>
      </div>

      <p class="text-center text-white font-medium">
        {@goal.message}
      </p>
    </div>
    """
  end

  @doc """
  Renders a quick action button with icon and label.

  ## Examples

      <.quick_action_button
        icon="hero-calendar"
        label="Book Activity"
        bg_color={Theme.bg(:primary_light)}
        icon_color={Theme.text_color(:primary)}
        phx-click="book_activity"
      />
  """
  attr :icon, :string, required: true, doc: "Heroicon name"
  attr :label, :string, required: true
  attr :bg_color, :string, required: true, doc: "Background color for icon container"
  attr :icon_color, :string, required: true, doc: "Icon color"
  attr :class, :string, default: ""
  attr :rest, :global, include: ~w(phx-click phx-value-* disabled)

  def quick_action_button(assigns) do
    ~H"""
    <button
      type="button"
      class={[
        "bg-white p-4 shadow-sm border border-hero-grey-200",
        Theme.rounded(:xl),
        "hover:shadow-md hover:scale-[1.02]",
        Theme.transition(:normal),
        "group",
        @class
      ]}
      {@rest}
    >
      <.gradient_icon
        gradient_class={@bg_color}
        size="sm"
        shape="circle"
        class={"mb-3 group-hover:#{String.replace(@bg_color, "100", "200")} #{Theme.transition(:normal)}"}
      >
        <.icon name={@icon} class={"w-5 h-5 #{@icon_color}"} />
      </.gradient_icon>
      <div class="text-sm font-medium text-hero-black">{@label}</div>
    </button>
    """
  end

  @doc """
  Renders a payment option radio button with title and description.

  ## Examples

      <.payment_option
        value="card"
        title="Credit Card"
        description="Pay securely with Visa, Mastercard, or other cards"
        selected={@payment_method == "card"}
        phx-click="select_payment_method"
        phx-value-method="card"
      />
  """
  attr :value, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :selected, :boolean, required: true
  attr :name, :string, default: "payment_method"
  attr :class, :string, default: ""
  attr :rest, :global, include: ~w(phx-click phx-value-* disabled)

  def payment_option(assigns) do
    ~H"""
    <label class={[
      "flex items-start gap-3 p-4 border-2 cursor-pointer",
      Theme.transition(:normal),
      Theme.rounded(:lg),
      if(@selected,
        do: [Theme.border_color(:primary), Theme.bg(:primary_light)],
        else: "border-hero-grey-200 hover:border-hero-grey-300"
      ),
      @class
    ]}>
      <input
        type="radio"
        name={@name}
        value={@value}
        checked={@selected}
        class="mt-1"
        {@rest}
      />
      <div>
        <div class={[Theme.typography(:card_title), "text-hero-black"]}>{@title}</div>
        <div class="text-sm text-[var(--fg-muted)]">{@description}</div>
      </div>
    </label>
    """
  end

  @doc """
  Renders the application footer with links and social media icons.

  ## Examples

      <.app_footer />
  """
  def app_footer(assigns) do
    ~H"""
    <footer class="bg-hero-black text-hero-grey-300 px-6 py-10 sm:p-10">
      <div class="grid grid-cols-1 md:grid-cols-4 gap-8 w-full max-w-6xl mx-auto">
        <div class="text-left">
          <h3 class="font-bold text-lg text-white mb-4">{gettext("Klass Hero")}</h3>
          <p class="text-sm">
            {gettext("Building the future of youth education by connecting communities.")}
          </p>
        </div>

        <div class="text-left">
          <h4 class="font-semibold mb-4">{gettext("Quick Links")}</h4>
          <ul class="space-y-2 text-sm">
            <li>
              <.link navigate={~p"/programs"} class="link link-hover">{gettext("Programs")}</.link>
            </li>
            <li>
              <.link navigate={~p"/about"} class="link link-hover">{gettext("About Us")}</.link>
            </li>
            <li>
              <.link navigate={~p"/contact"} class="link link-hover">{gettext("Contact")}</.link>
            </li>
            <li>
              <.link navigate={~p"/for-providers"} class="link link-hover">
                {gettext("For Providers")}
              </.link>
            </li>
            <li>
              <.link navigate={~p"/trust-safety"} class="link link-hover">
                {gettext("Trust & Safety")}
              </.link>
            </li>
          </ul>
        </div>

        <div class="text-left">
          <h4 class="font-semibold mb-4">{gettext("Programs")}</h4>
          <ul class="space-y-2 text-sm">
            <li>
              <.link navigate={~p"/programs"} class="link link-hover">{gettext("Afterschool")}</.link>
            </li>
            <li>
              <.link navigate={~p"/programs"} class="link link-hover">
                {gettext("Summer Camps")}
              </.link>
            </li>
            <li>
              <.link navigate={~p"/programs"} class="link link-hover">{gettext("Class Trips")}</.link>
            </li>
            <li>
              <.link navigate={~p"/programs"} class="link link-hover">{gettext("Enrichment")}</.link>
            </li>
          </ul>
        </div>

        <div class="text-left">
          <h4 class="font-semibold mb-4">{gettext("Connect")}</h4>
          <div :if={KlassHero.SocialLinks.all() != []} class="flex gap-2 mb-4">
            <a
              :for={{network, label, url} <- KlassHero.SocialLinks.all()}
              href={url}
              target="_blank"
              rel="noopener noreferrer"
              aria-label={gettext("Klass Hero on %{network}", network: label)}
              class={[
                "inline-flex items-center justify-center w-11 h-11",
                Theme.rounded(:full),
                "hover:bg-base-200",
                Theme.transition(:normal)
              ]}
            >
              <.kh_social_icon network={network} />
            </a>
          </div>
          <div class="text-sm">
            <p :if={KlassHero.Contact.email()}>Email: {KlassHero.Contact.email()}</p>
            <p :if={KlassHero.Contact.phone()}>Phone: {KlassHero.Contact.phone()}</p>
          </div>
        </div>
      </div>

      <div class="border-t border-base-300 pt-6 mt-6 w-full max-w-6xl mx-auto text-center">
        <p class="text-sm">
          &copy; {Date.utc_today().year} Klass Hero. {gettext("All rights reserved.")}
        </p>
        <div class="flex gap-4 justify-center mt-2 text-xs">
          <.link navigate={~p"/privacy"} class="link link-hover">{gettext("Privacy Policy")}</.link>
          <span class="text-gray-400">•</span>
          <.link navigate={~p"/terms"} class="link link-hover">{gettext("Terms of Service")}</.link>
          <span class="text-gray-400">•</span>
          <.link navigate={~p"/trust-safety"} class="link link-hover">
            {gettext("Trust & Safety")}
          </.link>
        </div>
      </div>
    </footer>
    """
  end

  @doc """
  Renders a legal document page with hero, table of contents, content sections, and contact CTA.

  Used for pages that display structured document sections (Terms of Service, Privacy Policy, etc.).

  ## Security

  Section `content` values are rendered with `raw/1` and must be trusted, pre-sanitized HTML
  defined in application code. Never pass user-controlled input as section content.

  ## Examples

      <.document_page
        eyebrow_pill={gettext("Legal")}
        title={gettext("Terms of Service")}
        subtitle={gettext("Understanding our agreement with you")}
        last_updated="December 12, 2025"
        sections={terms_sections()}
        cta_title={gettext("Questions About These Terms?")}
        cta_body={gettext("We're here to clarify any questions you may have.")}
      />
  """
  attr :title, :string, required: true, doc: "Page title (already translated)"
  attr :subtitle, :string, required: true, doc: "Page subtitle (already translated)"
  attr :last_updated, :string, required: true, doc: "Last updated date string"

  attr :eyebrow_pill, :string,
    default: nil,
    doc: "Optional outline pill rendered above the title in the marketing hero"

  attr :sections, :list,
    required: true,
    doc: "List of section maps with keys: id, icon, gradient, title, content"

  attr :cta_title, :string, required: true, doc: "CTA heading text (already translated)"
  attr :cta_body, :string, required: true, doc: "CTA body text (already translated)"

  def document_page(assigns) do
    ~H"""
    <.mk_page_hero eyebrow_icon="hero-document-text" pill={@eyebrow_pill}>
      <:title>{@title}</:title>
      <:lede>{@subtitle}</:lede>
    </.mk_page_hero>

    <div class="max-w-4xl mx-auto p-6 space-y-6">
      <%!-- Last Updated Banner --%>
      <div class="bg-hero-blue-50 border border-hero-blue-200 rounded-lg p-4">
        <p class="text-sm text-hero-blue-800">
          <span class="font-semibold">{gettext("Last Updated:")}</span> {@last_updated}
        </p>
      </div>

      <%!-- Table of Contents Card --%>
      <.card>
        <:header>
          <h2 class={[Theme.typography(:section_title), Theme.text_color(:heading)]}>
            {gettext("Table of Contents")}
          </h2>
        </:header>
        <:body>
          <ul class="space-y-2">
            <li :for={section <- @sections}>
              <a
                href={"##{section.id}"}
                class="text-hero-blue-600 hover:underline flex items-center gap-2"
              >
                <.icon name={section.icon} class="w-4 h-4" />
                {section.title}
              </a>
            </li>
          </ul>
        </:body>
      </.card>

      <%!-- Document Sections --%>
      <.card :for={section <- @sections} id={section.id}>
        <:header>
          <div class="flex items-center gap-3">
            <.gradient_icon gradient_class={section.gradient} size="sm" shape="circle">
              <.icon name={section.icon} class="w-5 h-5 text-white" />
            </.gradient_icon>
            <h2 class={[Theme.typography(:section_title), Theme.text_color(:heading)]}>
              {section.title}
            </h2>
          </div>
        </:header>
        <:body>
          <div class={["prose prose-sm max-w-none", Theme.text_color(:secondary)]}>
            <%!-- Sections come from terms_sections/0 and privacy_sections/0: developer-
            authored HTML whose one dynamic value (Contact.email/0) is html_escape'd at
            the source. No user input reaches this.
            raw-html-lint-ignore --%>
            {raw(section.content)}
          </div>
        </:body>
      </.card>
    </div>

    <.mk_cta_section title={@cta_title} lede={@cta_body}>
      <:cta>
        <.link navigate={~p"/contact"}>
          <.kh_button variant={:primary} size={:lg}>{gettext("Contact Us")}</.kh_button>
        </.link>
      </:cta>
    </.mk_cta_section>
    """
  end

  @doc """
  Renders a public, read-only provider identity at two densities: `:compact` for a
  sidebar card (program detail), `:full` for a page hero.

  Takes a plain view map from `ProviderPresenter.to_public_view/2`. Everything
  except `business_name` and `initials` is optional — a provider who has filled in
  nothing still renders, which is the common case today.

  ## Examples

      <.provider_hero provider={@provider_profile} />
      <.provider_hero provider={@provider_profile} variant={:full} />
  """
  attr :provider, :map,
    required: true,
    doc: """
    Public provider view: %{business_name, initials, description, logo_url,
    tagline, cover_image_url, social_links, trust_state}
    """

  attr :variant, :atom, default: :compact, values: [:compact, :full]

  def provider_hero(%{variant: :compact} = assigns) do
    ~H"""
    <section
      id="provider-profile-card"
      data-variant="compact"
      class={[
        Theme.bg(:surface),
        Theme.rounded(:xl),
        "shadow-sm border overflow-hidden",
        Theme.border_color(:light)
      ]}
    >
      <div class={["p-4 border-b", Theme.border_color(:light)]}>
        <h3 class={["font-semibold flex items-center gap-2", Theme.text_color(:heading)]}>
          <.icon name="hero-building-storefront" class="w-5 h-5 text-hero-blue-500" />
          {gettext("About the Provider")}
        </h3>
      </div>
      <div class="p-6 flex items-start gap-4">
        <.provider_avatar provider={@provider} size="w-16 h-16" text="text-xl" />
        <div class="flex-1 min-w-0">
          <div class="flex flex-wrap items-center gap-2">
            <h4 class={[Theme.typography(:card_title), Theme.text_color(:heading)]}>
              <%!-- Linked only when an id is present: a hand-built map from a test or
                    preview must not crash the page (#1073). The :full variant is the
                    profile page itself, so it never links. --%>
              <.link
                :if={@provider[:id]}
                navigate={~p"/providers/#{@provider.id}"}
                class="hover:text-[var(--fg-link)] hover:underline"
              >
                {@provider.business_name}
              </.link>
              <span :if={!@provider[:id]}>{@provider.business_name}</span>
            </h4>
            <.kh_trust_mark state={trust_state(@provider)} variant={:compact} />
          </div>
          <p
            :if={present?(@provider[:tagline])}
            class={["text-sm mt-1", Theme.text_color(:secondary_dark)]}
          >
            {@provider.tagline}
          </p>
          <p
            :if={present?(@provider[:description])}
            class={["text-sm leading-relaxed mt-1", Theme.text_color(:secondary_dark)]}
          >
            {@provider.description}
          </p>
          <.provider_social_row provider={@provider} class="mt-3" />
        </div>
      </div>
    </section>
    """
  end

  def provider_hero(%{variant: :full} = assigns) do
    ~H"""
    <section id="provider-hero" data-variant="full">
      <%!-- The band carries no text, which is what lets the cover paint at full
            contrast: there is nothing here for a scrim to protect. Keep it that
            way — text over an arbitrary upload has unbounded contrast. --%>
      <div class={[Theme.rounded(:xl), "overflow-hidden"]}>
        <img
          :if={present?(@provider[:cover_image_url])}
          src={@provider.cover_image_url}
          alt=""
          data-band="cover"
          class="w-full h-32 sm:h-44 object-cover"
        />
        <%!-- Shorter than the cover band on purpose. A photo earns the height; an
              empty gradient at the same size outgrows the identity card beneath
              it (176px of colour above 154px of content), and reads as a slot
              waiting to be filled — which is most profiles today. --%>
        <div
          :if={!present?(@provider[:cover_image_url])}
          data-band="gradient"
          class={["w-full h-20 sm:h-28", Theme.gradient(:primary)]}
        >
        </div>
      </div>

      <%!-- Opaque by contract, not by taste: the contrast audit resolves a text
            node's background by walking its ancestors, and this card is the
            ancestor standing between every string below and the photo. --%>
      <div
        data-testid="provider-identity-card"
        class={[
          Theme.bg(:surface),
          Theme.rounded(:xl),
          "relative z-10 -mt-6 mx-4 sm:mx-8 px-6 pt-14 sm:pt-16 pb-6",
          "flex flex-col items-center gap-2 text-center shadow-sm border",
          Theme.border_color(:light)
        ]}
      >
        <%!-- Anchored to the card, not the band, so the band keeps overflow-hidden
              for its own rounding without clipping the avatar. The -top offset is
              half the avatar's height at each breakpoint (40 of 80, 48 of 96) —
              that is what centres the medallion on the seam, so the two pairs move
              together or not at all.

              Elevation is load-bearing here, not decoration: with no cover the band
              and the initials fallback both carry gradient(:primary), and they read
              apart only because each interpolates across its own box. --%>
        <div class={[
          "absolute -top-10 sm:-top-12 left-1/2 -translate-x-1/2 flex border-4 border-white",
          Theme.rounded(:full),
          Theme.shadow(:md)
        ]}>
          <.provider_avatar provider={@provider} size="w-20 h-20 sm:w-24 sm:h-24" text="text-2xl" />
        </div>

        <%!-- :page_title, not :section_title — the latter is what "About the
              Provider" further down the page uses, and the name must not tie with
              it. Matches program_detail_live.ex, the sibling hero. --%>
        <h1 class={[Theme.typography(:page_title), Theme.text_color(:heading)]}>
          {@provider.business_name}
        </h1>

        <%!-- No guard, no per-child margins: `gap` falls only between children that
              actually render, and both the trust mark and the social row render
              nothing when they have nothing to say. Re-checking :unverified here
              would be a second copy of a rule kh_trust_mark already owns. --%>
        <.kh_trust_mark state={trust_state(@provider)} />

        <p
          :if={present?(@provider[:tagline])}
          class={[Theme.typography(:body), "text-[var(--fg-muted-on-light)]"]}
        >
          {@provider.tagline}
        </p>

        <.provider_social_row provider={@provider} class="mt-2 justify-center" />
      </div>
    </section>
    """
  end

  attr :provider, :map, required: true
  attr :size, :string, required: true
  attr :text, :string, required: true

  defp provider_avatar(assigns) do
    ~H"""
    <img
      :if={present?(@provider[:logo_url])}
      src={@provider.logo_url}
      alt={@provider.business_name}
      class={[@size, "object-cover flex-shrink-0", Theme.rounded(:full)]}
    />
    <div
      :if={!present?(@provider[:logo_url])}
      class={[
        @size,
        @text,
        "flex items-center justify-center text-white font-bold flex-shrink-0",
        Theme.rounded(:full),
        Theme.gradient(:primary)
      ]}
    >
      {@provider.initials}
    </div>
    """
  end

  attr :provider, :map, required: true
  attr :class, :string, default: ""

  defp provider_social_row(assigns) do
    ~H"""
    <div :if={social_links(@provider) != []} class={["flex flex-wrap items-center gap-1", @class]}>
      <a
        :for={{network, label, url} <- social_links(@provider)}
        href={url}
        target="_blank"
        rel="noopener noreferrer"
        aria-label={
          gettext("%{business} on %{network}", business: @provider.business_name, network: label)
        }
        class={[
          "inline-flex items-center justify-center w-11 h-11",
          Theme.rounded(:full),
          Theme.text_color(:secondary_dark),
          "hover:bg-hero-grey-100 hover:text-hero-blue-600",
          Theme.transition(:normal)
        ]}
      >
        <.kh_social_icon network={network} />
      </a>
    </div>
    """
  end

  # Access with a default: a hand-built map from a test or preview must not crash
  # the page the way a missing key would (#1073).
  defp social_links(provider), do: provider[:social_links] || []
  defp trust_state(provider), do: provider[:trust_state] || :unverified

  defp present?(nil), do: false
  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: true
end
