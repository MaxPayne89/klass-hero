defmodule KlassHeroWeb.ProviderLayoutComponents do
  @moduledoc """
  Function components for the authenticated provider surface.

  Mirrors the `Pv*` primitives in `design_handoff/provider_app/Sections.jsx`.
  Held separate from the existing `provider_components.ex` (which is large
  and domain-specific) so the layout vocabulary can evolve independently.

  Sidebar is BLACK with a yellow active accent — intentional contrast with
  the parent surface's white-with-blue sidebar.
  """

  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: KlassHeroWeb.Endpoint,
    router: KlassHeroWeb.Router,
    statics: KlassHeroWeb.static_paths()

  use Gettext, backend: KlassHeroWeb.Gettext

  import KlassHeroWeb.ProviderComponents,
    only: [provider_dashboard_header: 1, provider_nav_tabs: 1]

  import KlassHeroWeb.UIComponents,
    only: [
      kh_logo: 1,
      kh_card: 1,
      kh_pill: 1,
      kh_icon_chip: 1,
      kh_list_row: 1,
      kh_user_menu: 1,
      icon: 1
    ]

  alias KlassHeroWeb.Theme

  @desktop_items [
    {:home, "Overview", "hero-home", "/provider/dashboard"},
    {:programs, "Programs", "hero-book-open", "/provider/dashboard/programs"},
    {:roster, "Sessions", "hero-users", "/provider/sessions"},
    {:calendar, "Schedule", "hero-calendar", nil},
    {:messages, "Comms", "hero-inbox", "/provider/messages"},
    {:settings, "Settings", "hero-cog-6-tooth", "/users/settings"}
  ]

  @mobile_tabs [
    {:home, "Overview", "hero-home", "/provider/dashboard"},
    {:roster, "Sessions", "hero-users", "/provider/sessions"},
    {:messages, "Comms", "hero-inbox", "/provider/messages"}
  ]

  @doc """
  Provider sidebar (desktop) + bottom-tab nav (mobile).

  `active` accepts page-scoped keys that don't all map to a sidebar item.
  Pages without a sidebar entry (e.g. subscription, onboarding) pass their
  own key so nothing lights up — preferable to defaulting to `:home`, which
  would falsely highlight Overview. Settings points at the shared account
  page, which now renders in this chrome; the rest of #804 is outstanding.
  """
  attr :active, :atom,
    required: true,
    values: [:home, :programs, :roster, :calendar, :messages, :settings, :subscription, :onboarding]

  def pv_sidebar(assigns) do
    assigns = assign(assigns, items: @desktop_items, tabs: @mobile_tabs)

    ~H"""
    <aside class="hidden lg:flex w-[220px] shrink-0 h-screen sticky top-0 bg-black text-white flex-col">
      <div class="p-5 border-b border-white/10">
        <.link navigate={~p"/"} class="flex items-center" aria-label="Klass Hero">
          <.kh_logo size={28} />
        </.link>
        <div class="text-[11px] text-white/60 uppercase tracking-wider font-bold mt-3">
          {gettext("Provider")}
        </div>
      </div>
      <nav class="p-3 flex-1" aria-label={gettext("Provider navigation")}>
        <.pv_sidebar_link
          :for={{key, label, icon, href} <- @items}
          key={key}
          label={label}
          icon={icon}
          href={href}
          active?={@active == key}
        />
      </nav>
      <div class="p-4 border-t border-white/10">
        <div class="p-3 rounded-xl bg-white/5">
          <div class="flex items-center gap-2 text-xs text-white/70">
            <.icon name="hero-sparkles" class="w-3.5 h-3.5" /> {gettext("Pro tip")}
          </div>
          <p class="mt-1 text-xs text-white/90 leading-relaxed">
            {gettext("Add 3+ photos to boost bookings by ~40%.")}
          </p>
        </div>
      </div>
    </aside>

    <nav
      class="lg:hidden fixed bottom-0 left-0 right-0 z-40 bg-black flex items-stretch h-[64px] pb-[env(safe-area-inset-bottom)] shadow-[0_-4px_16px_rgba(0,0,0,.18)]"
      aria-label={gettext("Provider bottom navigation")}
    >
      <.pv_bottom_tab
        :for={{key, label, icon, href} <- @tabs}
        key={key}
        label={label}
        icon={icon}
        href={href}
        active?={@active == key}
      />
    </nav>
    """
  end

  attr :key, :atom, required: true
  attr :label, :string, required: true
  attr :icon, :string, required: true
  attr :href, :string, default: nil
  attr :active?, :boolean, default: false

  defp pv_sidebar_link(assigns) do
    ~H"""
    <a
      :if={@href}
      href={@href}
      class={[
        "group relative flex items-center gap-3 pl-4 pr-3 py-2.5 rounded-xl mb-1 transition-all font-semibold text-sm no-underline",
        @active? && "bg-white/10 text-white",
        !@active? && "text-white/70 hover:bg-white/5 hover:text-white"
      ]}
      aria-current={@active? && "page"}
    >
      <span
        :if={@active?}
        class="absolute left-0 top-1.5 bottom-1.5 w-[3px] rounded-r-full bg-hero-yellow-500"
        aria-hidden="true"
      ></span>
      <.icon
        name={@icon}
        class={"w-5 h-5 shrink-0 transition-colors #{pv_sidebar_icon_class(@active?)}"}
      />
      {@label}
    </a>
    <span
      :if={!@href}
      class="flex items-center gap-3 pl-4 pr-3 py-2.5 rounded-xl mb-1 font-semibold text-sm text-white/40 cursor-not-allowed"
      title={gettext("Coming soon")}
    >
      <.icon name={@icon} class="w-5 h-5 opacity-60 shrink-0" /> {@label}
    </span>
    """
  end

  defp pv_sidebar_icon_class(true), do: "text-hero-yellow-500"
  defp pv_sidebar_icon_class(false), do: "text-white/70 group-hover:text-white"

  attr :key, :atom, required: true
  attr :label, :string, required: true
  attr :icon, :string, required: true
  attr :href, :string, default: nil
  attr :active?, :boolean, default: false

  defp pv_bottom_tab(assigns) do
    ~H"""
    <a
      :if={@href}
      href={@href}
      aria-current={@active? && "page"}
      class={[
        "relative flex-1 flex flex-col items-center justify-center gap-1 no-underline transition-colors",
        @active? && "text-hero-yellow-500",
        !@active? && "text-white/60 hover:text-white"
      ]}
    >
      <span
        :if={@active?}
        class="absolute top-0 w-10 h-[3px] rounded-b-full bg-hero-yellow-500"
        aria-hidden="true"
      ></span>
      <.icon name={@icon} class="w-6 h-6" />
      <span class={[
        "text-[10px] tracking-tight",
        if(@active?, do: "font-bold", else: "font-semibold")
      ]}>
        {@label}
      </span>
    </a>
    """
  end

  @doc """
  Provider topbar with provider identity, verified pill, and trailing CTAs.

  `provider` shape: `%{name, tagline, verified?: boolean}`. Mobile shrinks
  to a sticky compact header.
  """
  attr :provider, :map, required: true
  attr :show_new_program_cta, :boolean, default: false
  attr :user, :map, required: true, doc: "Current user; needs :name and :email"

  attr :personas, :list, default: [], doc: "Personas this account holds; drives the switcher."
  attr :active_persona, :atom, default: nil, doc: "The persona currently being viewed."

  def pv_topbar(assigns) do
    ~H"""
    <div class="hidden lg:flex px-8 py-6 bg-white border-b border-hero-grey-200 items-center justify-between">
      <div class="flex items-center gap-4">
        <div class={pv_topbar_avatar_desktop_classes()}>
          {String.first(@provider[:name] || "?") |> String.upcase()}
        </div>
        <div>
          <div class="flex items-center gap-2">
            <span class={pv_topbar_title_classes()}>{@provider[:name]}</span>
            <.kh_pill :if={@provider[:verified?]} tone={:success}>
              <.icon name="hero-shield-check" class="w-3 h-3" /> {gettext("Verified")}
            </.kh_pill>
          </div>
          <div :if={@provider[:tagline]} class="text-sm text-[var(--fg-muted)] mt-0.5">
            {@provider.tagline}
          </div>
        </div>
      </div>
      <div class="flex items-center gap-2">
        <a
          :if={@show_new_program_cta}
          href="/provider/dashboard/edit"
          class={pv_topbar_primary_button_classes()}
        >
          <.icon name="hero-plus" class="w-4 h-4" /> {gettext("New program")}
        </a>
        <.kh_user_menu
          user={@user}
          personas={@personas}
          active_persona={@active_persona}
          id="provider-user-menu-desktop"
        />
      </div>
    </div>

    <div class="lg:hidden sticky top-0 z-30 bg-white/95 backdrop-blur-sm border-b border-hero-grey-200 px-4 h-14 flex items-center gap-3">
      <.link navigate={~p"/"} class="flex items-center shrink-0" aria-label="Klass Hero">
        <.kh_logo size={26} />
      </.link>
      <div class={pv_topbar_avatar_mobile_classes()}>
        {String.first(@provider[:name] || "?") |> String.upcase()}
      </div>
      <div class="flex-1 min-w-0 flex items-center gap-1.5">
        <span class={pv_topbar_mobile_title_classes()}>{@provider[:name]}</span>
        <.icon
          :if={@provider[:verified?]}
          name="hero-shield-check"
          class="w-3.5 h-3.5 text-emerald-500 shrink-0"
        />
      </div>
      <.kh_user_menu
        user={@user}
        personas={@personas}
        active_persona={@active_persona}
        id="provider-user-menu-mobile"
        class="shrink-0"
      />
    </div>
    """
  end

  @doc """
  Provider dashboard chrome — header band + horizontal tab nav, with the
  page's content rendered as the inner block underneath.

  Composed by every LiveView that should feel like a tab on the provider
  dashboard. The shell knows nothing about which LV uses it — callers pass
  their `business` and the `current_tab` atom
  (`:overview`, `:team`, `:programs`, `:sessions`).

  ## Examples

      <.pv_dashboard_chrome business={@business} current_tab={:sessions}>
        <.sessions_section ... />
      </.pv_dashboard_chrome>
  """
  attr :business, :map, required: true

  attr :current_tab, :atom,
    required: true,
    values: [:overview, :team, :programs, :sessions]

  slot :inner_block, required: true

  def pv_dashboard_chrome(assigns) do
    ~H"""
    <div class={["min-h-screen", Theme.bg(:muted)]}>
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
        <.provider_dashboard_header business={@business} />
        <.provider_nav_tabs current_tab={@current_tab} />
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  Shared shell for the tab-based provider dashboard sub-LiveViews
  (Overview / Team / Programs).

  Wraps `pv_dashboard_chrome` with the profile-completion banner and the
  dual-role cross-navigation link that every tab renders, so each sub-LiveView
  supplies only its own section via the inner block. Edit renders its own bare
  shell and does not use this.
  """
  attr :business, :map, required: true

  attr :current_tab, :atom,
    required: true,
    values: [:overview, :team, :programs]

  attr :profile_draft?, :boolean, default: false
  attr :dual_role?, :boolean, default: false

  slot :inner_block, required: true

  def pv_dashboard_shell(assigns) do
    ~H"""
    <.pv_dashboard_chrome business={@business} current_tab={@current_tab}>
      <.profile_completion_banner :if={@profile_draft?} />
      <.link
        :if={@dual_role?}
        id="cross-nav-staff-link"
        navigate={~p"/staff/dashboard"}
        class="inline-flex items-center gap-1 text-sm text-brand hover:text-brand/80"
      >
        {gettext("View your assignments")} →
      </.link>

      {render_slot(@inner_block)}
    </.pv_dashboard_chrome>
    """
  end

  defp profile_completion_banner(assigns) do
    ~H"""
    <div
      id="profile-completion-banner"
      class={[
        "mb-6 p-4 border-2 border-amber-300 bg-amber-50",
        Theme.rounded(:xl)
      ]}
    >
      <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
        <div class="flex items-start gap-3">
          <.icon name="hero-exclamation-triangle" class="w-6 h-6 text-amber-500 flex-shrink-0 mt-0.5" />
          <div>
            <h3 class={["font-semibold", Theme.typography(:card_title)]}>
              {gettext("Complete your provider profile")}
            </h3>
            <p class="text-sm text-gray-500 mt-0.5">
              {gettext(
                "Fill in your business details so parents can find you. Your profile will be reviewed by Klass Hero before going live."
              )}
            </p>
          </div>
        </div>
        <.link
          navigate={~p"/provider/complete-profile"}
          class={[
            "inline-flex items-center justify-center px-4 py-2 text-sm font-medium text-white whitespace-nowrap",
            Theme.rounded(:lg),
            Theme.gradient(:primary)
          ]}
        >
          {gettext("Complete Profile")}
        </.link>
      </div>
    </div>
    """
  end

  @doc """
  Provider stat card. Maps to bundle's `PvStatCard` (Sections.jsx:115).

  `trend` is an optional integer percentage delta — if `nil`, the up/down
  arrow is hidden. Per Q3.4 the dashboard ships with `trend=nil` until
  historical comparison queries land.
  """
  attr :title, :string, required: true
  attr :value, :string, required: true
  attr :caption, :string, default: nil
  attr :icon, :string, required: true
  attr :tone, :atom, default: :primary
  attr :trend, :integer, default: nil
  attr :disabled, :boolean, default: false

  def pv_stat_card(assigns) do
    ~H"""
    <.kh_card class={"p-5 #{if @disabled, do: "opacity-60", else: ""}"}>
      <div class="flex items-center justify-between mb-3">
        <.kh_icon_chip icon={@icon} gradient={@tone} size={:sm} />
        <span
          :if={@trend}
          class={[
            "text-xs font-bold",
            if(@trend > 0, do: "text-emerald-600", else: "text-red-500")
          ]}
        >
          {if @trend > 0, do: "↑", else: "↓"} {abs(@trend)}%
        </span>
      </div>
      <div class={pv_stat_value_classes()}>{@value}</div>
      <div class="mt-1 text-[13px] text-[var(--fg-muted)] font-semibold">{@title}</div>
      <div :if={@caption} class="text-xs text-[var(--fg-muted)] mt-1">{@caption}</div>
    </.kh_card>
    """
  end

  @doc """
  Earnings chart placeholder.

  `data` is a list of `%{w: "W1", v: 1200}` maps. When the list is empty,
  renders a generic "coming soon" explainer card.
  """
  attr :data, :list, default: []

  def pv_earnings_chart(assigns) do
    ~H"""
    <.kh_card class="p-6">
      <div class="flex items-center justify-between mb-5">
        <div>
          <h3 class="font-bold text-lg">{gettext("Earnings trend")}</h3>
          <div class="text-sm text-[var(--fg-muted)]">{gettext("Last 8 weeks")}</div>
        </div>
        <div class="flex gap-2">
          <.kh_pill tone={:dark}>{gettext("Week")}</.kh_pill>
          <.kh_pill tone={:outline}>{gettext("Month")}</.kh_pill>
          <.kh_pill tone={:outline}>{gettext("Year")}</.kh_pill>
        </div>
      </div>
      <div :if={@data == []} class="py-12 text-center text-sm text-[var(--fg-muted)]">
        {gettext("Earnings tracking is coming soon.")}
      </div>
      <div :if={@data != []} class="flex items-end gap-2 h-40 px-1">
        <.pv_chart_bar :for={d <- @data} datum={d} max={chart_max(@data)} />
      </div>
    </.kh_card>
    """
  end

  attr :datum, :map, required: true
  attr :max, :integer, required: true

  defp pv_chart_bar(assigns) do
    height = round(assigns.datum.v / max(assigns.max, 1) * 100)
    assigns = assign(assigns, height: height)

    ~H"""
    <div class="flex-1 flex flex-col items-center gap-2 group">
      <div
        class="w-full rounded-t-lg bg-gradient-to-t from-hero-blue-500 to-hero-blue-300 transition-all hover:from-hero-yellow-500 hover:to-hero-yellow-300 relative"
        style={"height: #{@height}%"}
      >
        <div class="absolute -top-7 left-1/2 -translate-x-1/2 bg-black text-white px-2 py-0.5 rounded text-[10px] font-bold opacity-0 group-hover:opacity-100 transition-opacity whitespace-nowrap">
          €{@datum.v}
        </div>
      </div>
      <div class="text-[10px] text-[var(--fg-muted)] font-semibold">{@datum.w}</div>
    </div>
    """
  end

  defp chart_max(data), do: data |> Enum.map(& &1.v) |> Enum.max(fn -> 1 end)

  @doc """
  Compact program-row primitive used by dashboard + sessions screens.

  `program` keys: `:id, :title, :status, :cover_image_url` (a plain image URL,
  or nil for the gradient fallback).
  """
  attr :program, :map, required: true
  attr :on_edit, :string, default: "edit_program"

  def pv_program_row(assigns) do
    ~H"""
    <.kh_list_row hover>
      <:media>
        <div class="w-14 h-14 rounded-xl overflow-hidden">
          <img
            :if={@program[:cover_image_url]}
            id={"pv-program-cover-#{@program[:id]}"}
            src={@program[:cover_image_url]}
            alt={@program.title}
            loading="lazy"
            class="w-full h-full object-cover"
          />
          <div
            :if={!@program[:cover_image_url]}
            class="w-full h-full"
            style="background: linear-gradient(135deg,#33CFFF,#FFFF36)"
          >
          </div>
        </div>
      </:media>
      <:title>{@program.title}</:title>
      <:pill :if={@program[:status]}>
        <.kh_pill tone={status_tone(@program.status)}>{to_string(@program.status)}</.kh_pill>
      </:pill>
      <:actions>
        <button
          type="button"
          phx-click={@on_edit}
          phx-value-program-id={@program[:id]}
          aria-label={gettext("Edit program")}
          class="w-9 h-9 rounded-lg bg-white border border-hero-grey-200 flex items-center justify-center hover:bg-[var(--brand-primary)] hover:border-transparent"
        >
          <.icon name="hero-pencil" class="w-4 h-4" />
        </button>
      </:actions>
    </.kh_list_row>
    """
  end

  defp status_tone(:live), do: :success
  defp status_tone(:draft), do: :cream
  defp status_tone(:full), do: :error
  defp status_tone(_), do: :warning

  @doc """
  Today's session roster card with check-in toggles.

  `kids` is a list of `%{id, name, parent, present?: boolean, color}` maps.
  """
  attr :session, :map, required: true
  attr :kids, :list, required: true
  attr :on_check_in, :string, default: "check_in"
  attr :on_mark_all_present, :string, default: "mark_all_present"

  def pv_roster(assigns) do
    ~H"""
    <.kh_card class="p-5">
      <div class="flex items-center justify-between mb-4">
        <div>
          <h3 class="font-bold text-lg">{gettext("Today's check-ins")}</h3>
          <div :if={@session[:subtitle]} class="text-sm text-[var(--fg-muted)]">
            {@session.subtitle}
          </div>
        </div>
        <button
          type="button"
          phx-click={@on_mark_all_present}
          class="px-3 py-1.5 text-xs font-bold rounded-lg border border-hero-grey-300 hover:bg-hero-cream-100"
        >
          {gettext("Mark all present")}
        </button>
      </div>
      <div :if={@kids == []} class="text-sm text-[var(--fg-muted)]">
        {gettext("No registered children for this session.")}
      </div>
      <div class="space-y-1">
        <.kh_list_row
          :for={k <- @kids}
          density={:compact}
          hover
          meta={gettext("Parent: %{name}", name: k[:parent] || "—")}
        >
          <:media>
            <div
              class="w-9 h-9 rounded-full flex items-center justify-center font-bold text-black text-sm"
              style={"background: #{k[:color] || "#FFEAC9"}"}
            >
              {String.first(k.name || "?") |> String.upcase()}
            </div>
          </:media>
          <:title>{k.name}</:title>
          <:actions>
            <button
              type="button"
              phx-click={@on_check_in}
              phx-value-kid-id={k.id}
              aria-label={if k[:present?], do: gettext("Mark absent"), else: gettext("Mark present")}
              class={[
                "w-7 h-7 rounded-full flex items-center justify-center transition-all",
                k[:present?] && "bg-emerald-500 text-white",
                !k[:present?] &&
                  "bg-hero-grey-100 text-[var(--fg-muted)] hover:bg-[var(--brand-primary)] hover:text-black"
              ]}
            >
              <.icon name="hero-check-circle" class="w-4 h-4" />
            </button>
          </:actions>
        </.kh_list_row>
      </div>
    </.kh_card>
    """
  end

  @doc """
  Pending enrollment card with an Approve button.

  `entry` keys: `:enrollment_id, :child_name, :program_title, :enrolled_at`.
  """
  attr :entry, :map, required: true

  def pv_pending_enrollment_card(assigns) do
    ~H"""
    <div
      id={"pending-enrollment-#{@entry.enrollment_id}"}
      class="flex items-center justify-between gap-3 rounded-xl border border-hero-grey-200 p-3"
    >
      <div class="min-w-0">
        <div class="font-semibold truncate">{@entry.child_name}</div>
        <div class="text-xs text-[var(--fg-muted)] truncate">{@entry.program_title}</div>
        <div class="text-xs text-[var(--fg-muted)]">
          {gettext("Enrolled")} {Calendar.strftime(@entry.enrolled_at, "%b %d")}
        </div>
      </div>
      <button
        id={"approve-enrollment-#{@entry.enrollment_id}"}
        type="button"
        phx-click="approve_enrollment"
        phx-value-id={@entry.enrollment_id}
        class="rounded-lg bg-[var(--brand-primary)] px-3 py-1.5 text-sm font-bold text-white hover:opacity-90"
      >
        {gettext("Approve")}
      </button>
    </div>
    """
  end

  ## Internal helpers

  # typography-lint-ignore: PvTopbar provider name uses display font
  defp pv_topbar_title_classes, do: "font-display font-extrabold tracking-tight text-2xl"

  defp pv_topbar_mobile_title_classes do
    # typography-lint-ignore: mobile compact provider name
    "font-display font-extrabold tracking-tight text-[15px] leading-none truncate"
  end

  defp pv_topbar_avatar_desktop_classes do
    # typography-lint-ignore: PvTopbar desktop avatar initial uses display font
    "w-14 h-14 rounded-2xl bg-gradient-to-br from-hero-blue-400 to-hero-yellow-500 flex items-center justify-center font-display font-extrabold text-2xl"
  end

  defp pv_topbar_avatar_mobile_classes do
    # typography-lint-ignore: PvTopbar mobile avatar initial uses display font
    "w-8 h-8 rounded-lg bg-gradient-to-br from-hero-blue-400 to-hero-yellow-500 flex items-center justify-center font-display font-extrabold text-sm shrink-0"
  end

  defp pv_topbar_primary_button_classes do
    # typography-lint-ignore: primary CTA mirrors KhButton primary surface
    "inline-flex items-center justify-center gap-2 px-3.5 py-2 text-sm rounded-lg font-display font-bold tracking-tight bg-[var(--brand-primary)] hover:bg-[var(--brand-primary-hover)] text-black"
  end

  defp pv_stat_value_classes do
    # typography-lint-ignore: PvStatCard value is numeric callout
    "font-display font-extrabold text-3xl tracking-tight"
  end
end
