defmodule KlassHeroWeb.ParentComponents do
  @moduledoc """
  Function components for the authenticated parent surface.

  Mirrors the `Pa*` primitives in `design_handoff/parent_app/Sections.jsx`.
  Each component is composable via the shared `Kh*` vocabulary in
  `KlassHeroWeb.UIComponents`.

  Sidebar, topbar, and bottom-tab nav share the same `:active_nav` atom so a
  LiveView only needs to set one assign to highlight the correct destination
  on every breakpoint.
  """

  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: KlassHeroWeb.Endpoint,
    router: KlassHeroWeb.Router,
    statics: KlassHeroWeb.static_paths()

  use Gettext, backend: KlassHeroWeb.Gettext

  import KlassHeroWeb.UIComponents,
    only: [kh_logo: 1, kh_card: 1, kh_pill: 1, kh_icon_chip: 1, kh_user_menu: 1, icon: 1]

  ## ---------------------------------------------------------------------------
  ## Sidebar + bottom-tab nav
  ## ---------------------------------------------------------------------------

  # Bookings entrypoint = `/programs` since parents start a new booking by
  # picking a program. There's no `/bookings` index today (no list-of-bookings
  # screen yet); the inline booking flow mounts at `/programs/:id/booking`.
  @desktop_items [
    {:home, "Dashboard", "hero-home", "/dashboard"},
    {:bookings, "Bookings", "hero-book-open", "/programs"},
    {:calendar, "Planner", "hero-calendar", nil},
    {:messages, "Messages", "hero-chat-bubble-left-right", "/messages"},
    {:children, "My Kids", "hero-users", "/family/settings/children"},
    {:participation, "Sessions", "hero-check-circle", "/participation"},
    {:billing, "Billing", "hero-currency-euro", nil},
    {:settings, "Settings", "hero-cog-6-tooth", "/users/settings"}
  ]

  @mobile_tabs [
    {:home, "Home", "hero-home", "/dashboard"},
    {:bookings, "Bookings", "hero-book-open", "/programs"},
    {:messages, "Messages", "hero-chat-bubble-left-right", "/messages"},
    {:participation, "Sessions", "hero-check-circle", "/participation"},
    {:children, "Kids", "hero-users", "/family/settings/children"}
  ]

  @doc """
  Parent sidebar (desktop ≥ lg) and bottom-tab nav (mobile < lg).

  Same component renders both — Tailwind breakpoint utilities switch which
  tree is visible. Bottom-tab limited to the 5 most-tapped destinations per
  bundle convention; the full nav stays in the desktop sidebar.
  """
  attr :active, :atom,
    required: true,
    values: [:home, :bookings, :calendar, :messages, :children, :participation, :billing, :settings]

  attr :user, :map, required: true, doc: "Current user; needs :name and :email"

  def pa_sidebar(assigns) do
    assigns = assign(assigns, items: @desktop_items, tabs: @mobile_tabs)

    ~H"""
    <aside class="hidden lg:flex w-[240px] shrink-0 h-screen sticky top-0 bg-white border-r border-hero-grey-200 flex-col">
      <div class="p-5 border-b border-hero-grey-200">
        <.link navigate={~p"/"} class="flex items-center" aria-label="Klass Hero">
          <.kh_logo size={32} />
        </.link>
      </div>
      <nav class="p-3 flex-1" aria-label={gettext("Parent navigation")}>
        <.pa_sidebar_link
          :for={{key, label, icon, href} <- @items}
          key={key}
          label={label}
          icon={icon}
          href={href}
          active?={@active == key}
        />
      </nav>
      <div class="p-3 border-t border-hero-grey-200">
        <a
          href="/users/settings"
          class="flex items-center gap-3 p-2 rounded-xl hover:bg-hero-cream-100 no-underline text-current"
          aria-label={gettext("Account settings")}
        >
          <div class="w-10 h-10 rounded-full bg-gradient-to-br from-hero-blue-400 to-hero-yellow-500 flex items-center justify-center font-bold text-black">
            {String.first(@user.name || @user.email || "?") |> String.upcase()}
          </div>
          <div class="flex-1 min-w-0">
            <div class="text-sm font-bold truncate">{@user.name || @user.email}</div>
            <div class="text-xs text-hero-grey-600 truncate">{@user.email}</div>
          </div>
          <.icon name="hero-cog-6-tooth" class="w-4 h-4 text-hero-grey-600" />
        </a>
      </div>
    </aside>

    <nav
      class="lg:hidden fixed bottom-0 left-0 right-0 z-40 bg-white border-t border-hero-grey-200 flex items-stretch h-[64px] pb-[env(safe-area-inset-bottom)] shadow-[0_-4px_16px_rgba(0,0,0,.04)]"
      aria-label={gettext("Parent bottom navigation")}
    >
      <.pa_bottom_tab
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

  defp pa_sidebar_link(assigns) do
    ~H"""
    <a
      :if={@href}
      href={@href}
      class={[
        "flex items-center gap-3 px-3 py-2.5 rounded-xl mb-1 transition-all font-semibold text-sm no-underline",
        @active? &&
          "bg-[var(--brand-primary)] text-black shadow-sm",
        !@active? && "text-hero-black-100 hover:bg-hero-cream-100"
      ]}
      aria-current={@active? && "page"}
    >
      <.icon name={@icon} class="w-5 h-5" /> {@label}
    </a>
    <span
      :if={!@href}
      class="flex items-center gap-3 px-3 py-2.5 rounded-xl mb-1 font-semibold text-sm text-hero-grey-500 cursor-not-allowed"
      title={gettext("Coming soon")}
    >
      <.icon name={@icon} class="w-5 h-5 opacity-60" /> {@label}
    </span>
    """
  end

  attr :key, :atom, required: true
  attr :label, :string, required: true
  attr :icon, :string, required: true
  attr :href, :string, default: nil
  attr :active?, :boolean, default: false

  defp pa_bottom_tab(assigns) do
    ~H"""
    <a
      :if={@href}
      href={@href}
      aria-current={@active? && "page"}
      class={[
        "relative flex-1 flex flex-col items-center justify-center gap-1 no-underline transition-colors",
        @active? && "text-[var(--brand-primary-dark)]",
        !@active? && "text-hero-grey-600 hover:text-hero-black-100"
      ]}
    >
      <span
        :if={@active?}
        class="absolute top-0 w-10 h-[3px] rounded-b-full bg-[var(--brand-primary)]"
        aria-hidden="true"
      ></span>
      <.icon name={@icon} class={"w-6 h-6 #{!@active? && "opacity-90"}"} />
      <span class={[
        "text-[10px] tracking-tight",
        if(@active?, do: "font-bold", else: "font-semibold")
      ]}>
        {@label}
      </span>
    </a>
    """
  end

  ## ---------------------------------------------------------------------------
  ## Topbar
  ## ---------------------------------------------------------------------------

  @doc """
  Parent topbar with title + subtitle + optional CTA / extra actions slot.

  Mobile shrinks to a sticky compact bar with the logo (since the sidebar
  is gone on small screens) and the page title.
  """
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :cta_label, :string, default: nil
  attr :cta_navigate, :string, default: nil
  attr :cta_icon, :string, default: "hero-plus"
  attr :user, :map, required: true, doc: "Current user; needs :name and :email"

  slot :extra_actions

  attr :personas, :list, default: [], doc: "Personas this account holds; drives the switcher."
  attr :active_persona, :atom, default: nil, doc: "The persona currently being viewed."

  def pa_topbar(assigns) do
    ~H"""
    <div class="hidden lg:flex px-8 pt-8 pb-6 bg-white border-b border-hero-grey-200 items-center justify-between">
      <div>
        <div :if={@subtitle} class="text-[13px] text-hero-grey-600 font-semibold">
          {@subtitle}
        </div>
        <h1 class={topbar_title_classes()}>{@title}</h1>
      </div>
      <div class="flex items-center gap-3">
        {render_slot(@extra_actions)}
        <.link
          :if={@cta_label && @cta_navigate}
          navigate={@cta_navigate}
          class={topbar_cta_classes()}
        >
          <.icon name={@cta_icon} class="w-4 h-4" /> {@cta_label}
        </.link>
        <.kh_user_menu
          user={@user}
          personas={@personas}
          active_persona={@active_persona}
          id="parent-user-menu-desktop"
        />
      </div>
    </div>

    <div class="lg:hidden sticky top-0 z-30 bg-white/95 backdrop-blur-sm border-b border-hero-grey-200 px-4 h-14 flex items-center gap-3">
      <.link navigate={~p"/"} class="flex items-center shrink-0" aria-label="Klass Hero">
        <.kh_logo size={26} />
      </.link>
      <div class="flex-1 min-w-0">
        <h1 class={topbar_mobile_title_classes()}>{@title}</h1>
        <div
          :if={@subtitle}
          class="text-[11px] text-hero-grey-600 font-semibold leading-none mt-1 truncate"
        >
          {@subtitle}
        </div>
      </div>
      <.kh_user_menu
        user={@user}
        personas={@personas}
        active_persona={@active_persona}
        id="parent-user-menu-mobile"
        class="shrink-0"
      />
    </div>
    """
  end

  ## ---------------------------------------------------------------------------
  ## Kid picker
  ## ---------------------------------------------------------------------------

  @doc """
  Horizontal scrollable kid picker (chip per child + add button).

  `kids` is a list of `%{id, name, age, programs, color}` maps. The picker
  hides on `< lg` per bundle convention — inline `lg:` switches the
  containing flex direction so each kid stays a tap target on tablet+.
  """
  attr :kids, :list, required: true
  attr :active_id, :any, default: nil
  attr :on_pick, :string, default: "pick-kid"
  attr :on_add, :string, default: "add-kid"

  def pa_kid_picker(assigns) do
    ~H"""
    <div class="flex items-center gap-3 overflow-x-auto pb-2" aria-label={gettext("Kid picker")}>
      <button
        :for={k <- @kids}
        type="button"
        phx-click={@on_pick}
        phx-value-id={k.id}
        aria-pressed={@active_id == k.id}
        class={[
          "flex items-center gap-2.5 pl-1 pr-4 py-1 rounded-full border-2 transition-all shrink-0",
          @active_id == k.id && "border-[var(--brand-primary)] bg-white shadow-md",
          @active_id != k.id && "border-transparent bg-white hover:border-hero-grey-300"
        ]}
      >
        <div
          class="w-9 h-9 rounded-full flex items-center justify-center font-bold text-black text-sm"
          style={"background: #{k[:color] || "#FFEAC9"}"}
        >
          {String.first(k.name || "?") |> String.upcase()}
        </div>
        <div class="text-left">
          <div class="text-sm font-bold leading-none">{k.name}</div>
          <div class="text-[10px] text-hero-grey-600 leading-tight mt-0.5">
            {k[:age]} · {k[:programs] || 0} {gettext("active")}
          </div>
        </div>
      </button>
      <button
        type="button"
        phx-click={@on_add}
        aria-label={gettext("Add a child")}
        class="w-11 h-11 rounded-full border-2 border-dashed border-hero-grey-300 flex items-center justify-center text-hero-grey-600 hover:border-[var(--brand-primary)] hover:text-[var(--brand-primary-dark)] shrink-0"
      >
        <.icon name="hero-plus" class="w-5 h-5" />
      </button>
    </div>
    """
  end

  ## ---------------------------------------------------------------------------
  ## Stat card
  ## ---------------------------------------------------------------------------

  attr :title, :string, required: true
  attr :value, :string, required: true
  attr :delta, :string, default: nil
  attr :icon, :string, required: true
  attr :tone, :atom, default: :primary, values: [:primary, :comic, :cool, :art, :safety]
  attr :disabled, :boolean, default: false, doc: "Render greyed-out 'Coming soon' card"

  def pa_stat_card(assigns) do
    ~H"""
    <.kh_card class={"p-5 #{if @disabled, do: "opacity-60", else: ""}"}>
      <div class="flex items-center justify-between">
        <span class="text-[13px] text-hero-grey-600 font-semibold">{@title}</span>
        <.kh_icon_chip icon={@icon} gradient={@tone} size={:sm} />
      </div>
      <div class="mt-3 flex items-baseline gap-2">
        <%!-- typography-lint-ignore: PaStatCard value uses display font as numeric callout --%>
        <span class="font-display font-extrabold text-3xl tracking-tight">{@value}</span>
        <span :if={@delta} class="text-xs font-bold text-emerald-600">{@delta}</span>
        <.kh_pill :if={@disabled} tone={:cream} class="ml-auto">
          {gettext("Coming soon")}
        </.kh_pill>
      </div>
    </.kh_card>
    """
  end

  ## ---------------------------------------------------------------------------
  ## Upcoming session item
  ## ---------------------------------------------------------------------------

  @doc """
  Renders one upcoming session row.

  `session` keys: `:month` (3-letter), `:day` (int/string), `:title`, `:time`,
  `:kid`, `:location`, `:status` (:confirmed | :pending | :cancelled).
  """
  attr :session, :map, required: true

  def pa_upcoming_item(assigns) do
    ~H"""
    <div class="flex items-center gap-4 p-4 rounded-xl hover:bg-hero-cream-100 transition-all">
      <div class="w-14 text-center shrink-0">
        <div class="text-[10px] font-bold text-[var(--brand-primary-dark)] uppercase">
          {@session.month}
        </div>
        <%!-- typography-lint-ignore: PaUpcomingItem day digit uses display font for emphasis --%>
        <div class="font-display font-extrabold text-3xl leading-none mt-0.5">
          {@session.day}
        </div>
      </div>
      <div class="w-px h-10 bg-hero-grey-200"></div>
      <div class="flex-1 min-w-0">
        <div class="font-bold truncate">{@session.title}</div>
        <div class="text-xs text-hero-grey-600 mt-0.5 flex items-center gap-2 flex-wrap">
          <span :if={@session[:time]} class="flex items-center gap-1">
            <.icon name="hero-clock" class="w-3 h-3" />{@session.time}
          </span>
          <span :if={@session[:time] && @session[:kid]}>·</span>
          <span :if={@session[:kid]}>{@session.kid}</span>
          <span :if={@session[:kid] && @session[:location]}>·</span>
          <span :if={@session[:location]}>{@session.location}</span>
        </div>
      </div>
      <.kh_pill tone={status_tone(@session[:status])}>
        {to_string(@session[:status] || :pending)}
      </.kh_pill>
    </div>
    """
  end

  defp status_tone(:confirmed), do: :success
  defp status_tone(:cancelled), do: :error
  defp status_tone(_), do: :warning

  ## ---------------------------------------------------------------------------
  ## Weekly goal
  ## ---------------------------------------------------------------------------

  @doc """
  Decorative weekly-goal progress card.

  Mock metric per Q2.7 — there's no backend feed for "sessions attended this
  week". Caller should pass `goal` (target int) and `done` (current int);
  if `goal` is `nil` the card becomes a placeholder with a "Coming soon" pill.
  """
  attr :goal, :integer, default: nil
  attr :done, :integer, default: 0

  def pa_weekly_goal(assigns) do
    pct =
      if is_nil(assigns.goal) || assigns.goal == 0 do
        0
      else
        min(100, round(assigns.done / assigns.goal * 100))
      end

    assigns = assign(assigns, pct: pct)

    ~H"""
    <.kh_card class="p-6 overflow-hidden relative">
      <div class="absolute -top-8 -right-8 w-32 h-32 rounded-full bg-hero-yellow-500 opacity-40">
      </div>
      <div class="absolute -bottom-12 -right-4 w-24 h-24 rounded-full bg-hero-blue-300 opacity-40">
      </div>
      <div class="relative">
        <.kh_pill tone={:dark} class="mb-2">{gettext("This week")}</.kh_pill>
        <h3 class={weekly_goal_title_classes()}>{gettext("Weekly adventure goal")}</h3>
        <p :if={@goal} class="text-sm text-hero-grey-600 mt-1">
          {gettext("%{done} of %{goal} sessions attended", done: @done, goal: @goal)}
        </p>
        <p :if={!@goal} class="text-sm text-hero-grey-600 mt-1">
          {gettext("Coming soon — track your family's weekly attendance.")}
        </p>
        <div class="mt-4 h-3 rounded-full bg-hero-grey-100 overflow-hidden">
          <div
            class="h-full rounded-full bg-gradient-to-r from-hero-blue-500 to-hero-blue-700 transition-all duration-500"
            style={"width: #{@pct}%"}
          >
          </div>
        </div>
        <div :if={@goal} class="mt-3 flex items-center justify-between">
          <span class="text-xs text-hero-grey-600">{@pct}% {gettext("complete")}</span>
          <span class={display_callout_classes()}>
            {max(0, @goal - @done)} {gettext("to go")} →
          </span>
        </div>
      </div>
    </.kh_card>
    """
  end

  ## ---------------------------------------------------------------------------
  ## Message preview list
  ## ---------------------------------------------------------------------------

  @doc """
  Compact recent-messages preview card.

  `messages` is a list of `%{id, from, preview, time, color, unread?}` maps.
  """
  attr :messages, :list, required: true
  attr :on_open_navigate, :string, default: "/messages"

  def pa_message_preview(assigns) do
    ~H"""
    <.kh_card class="p-5">
      <div class="flex items-center justify-between mb-4">
        <h3 class="font-bold text-lg">{gettext("Recent messages")}</h3>
        <.link navigate={@on_open_navigate} class="text-sm font-bold text-[var(--brand-primary-dark)]">
          {gettext("Open inbox")} →
        </.link>
      </div>
      <div :if={@messages == []} class="text-sm text-hero-grey-600">
        {gettext("No messages yet.")}
      </div>
      <div class="space-y-1">
        <div
          :for={m <- @messages}
          class="flex items-center gap-3 p-2.5 rounded-xl hover:bg-hero-cream-100"
        >
          <div
            class="w-10 h-10 rounded-full flex items-center justify-center font-bold text-sm text-black shrink-0"
            style={"background: #{m[:color] || "#FFEAC9"}"}
          >
            {String.first(m.from || "?") |> String.upcase()}
          </div>
          <div class="flex-1 min-w-0">
            <div class="flex items-center justify-between gap-3">
              <span class="font-bold text-sm truncate">{m.from}</span>
              <span :if={m[:time]} class="text-[11px] text-hero-grey-600 shrink-0">
                {m.time}
              </span>
            </div>
            <p class="text-xs text-hero-grey-600 truncate">{m[:preview]}</p>
          </div>
          <span
            :if={m[:unread?]}
            class="w-2 h-2 rounded-full bg-[var(--brand-primary)] shrink-0"
            aria-label={gettext("Unread")}
          ></span>
        </div>
      </div>
    </.kh_card>
    """
  end

  ## ---------------------------------------------------------------------------
  ## Family program card
  ## ---------------------------------------------------------------------------

  @doc """
  Enrolled-program tile with kid-avatar stack and category/title.

  `program` keys: `:id, :title, :category, :next, :provider, :status, :kids,
  :cover_image_url` (a plain image URL, or nil for the gradient fallback).
  """
  attr :program, :map, required: true

  def pa_family_program_card(assigns) do
    ~H"""
    <.kh_card class="overflow-hidden hover:shadow-lg transition-all">
      <div class="h-24 relative overflow-hidden">
        <img
          :if={@program[:cover_image_url]}
          id={"pa-program-cover-#{@program[:id]}"}
          src={@program[:cover_image_url]}
          alt={@program.title}
          loading="lazy"
          class="absolute inset-0 w-full h-full object-cover"
        />
        <div
          :if={!@program[:cover_image_url]}
          class="absolute inset-0"
          style="background: linear-gradient(90deg,#33CFFF,#FFFF36)"
        >
        </div>
        <div :if={@program[:status]} class="absolute top-2 right-2">
          <.kh_pill tone={status_tone(@program[:status])}>
            {to_string(@program[:status])}
          </.kh_pill>
        </div>
        <div :if={@program[:kids]} class="absolute bottom-2 left-2 flex -space-x-2">
          <div
            :for={k <- @program.kids}
            class="w-7 h-7 rounded-full border-2 border-white flex items-center justify-center text-xs font-bold text-black"
            style={"background: #{k[:color] || "#FFEAC9"}"}
          >
            {String.first(k.name || "?") |> String.upcase()}
          </div>
        </div>
      </div>
      <div class="p-4">
        <div
          :if={@program[:category]}
          class="text-[11px] text-hero-grey-600 font-semibold uppercase tracking-wide"
        >
          {@program.category}
        </div>
        <h4 class="font-bold text-base mt-0.5 leading-tight">{@program.title}</h4>
        <div :if={@program[:next]} class="mt-2 text-xs text-hero-grey-600 flex items-center gap-1.5">
          <.icon name="hero-calendar" class="w-3.5 h-3.5" /> {gettext("Next")} · {@program.next}
        </div>
        <div class="mt-3 pt-3 border-t border-hero-grey-200 flex items-center justify-between">
          <span :if={@program[:provider]} class="text-xs text-hero-grey-600">
            {@program.provider}
          </span>
          <span class={card_open_link_classes()}>{gettext("Open")} →</span>
        </div>
      </div>
    </.kh_card>
    """
  end

  ## ---------------------------------------------------------------------------
  ## Internal helpers
  ## ---------------------------------------------------------------------------

  # Class strings extracted so the typography-lint marker can sit on the
  # immediately preceding line. Phoenix's HEEx formatter rewrites multi-line
  # class strings, which makes inline same-line markers fragile.

  # typography-lint-ignore: PaTopbar desktop title is page chrome
  defp topbar_title_classes, do: "font-display font-extrabold tracking-tight text-3xl mt-1"

  # typography-lint-ignore: PaTopbar mobile title scales separately
  defp topbar_mobile_title_classes, do: "font-display font-extrabold tracking-tight text-[17px] leading-none truncate"

  defp topbar_cta_classes do
    # typography-lint-ignore: PaTopbar CTA mirrors KhButton primary surface
    "inline-flex items-center justify-center gap-2 px-5 py-2.5 text-sm rounded-xl bg-[var(--brand-primary)] hover:bg-[var(--brand-primary-hover)] text-black font-display font-bold tracking-tight"
  end

  # typography-lint-ignore: PaWeeklyGoal heading is part of card brand
  defp weekly_goal_title_classes, do: "font-display font-extrabold text-xl mt-2"

  # typography-lint-ignore: PaWeeklyGoal "to go" callout
  defp display_callout_classes, do: "font-display font-bold text-sm"

  # typography-lint-ignore: PaFamilyProgramCard "Open" CTA matches bundle
  defp card_open_link_classes, do: "text-xs font-bold font-display text-[var(--brand-primary-dark)]"
end
