defmodule KlassHeroWeb.UIComponents do
  @moduledoc "Reusable UI components following the Klass Hero design system."
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: KlassHeroWeb.Endpoint,
    router: KlassHeroWeb.Router,
    statics: KlassHeroWeb.static_paths()

  use Gettext, backend: KlassHeroWeb.Gettext

  alias KlassHeroWeb.Persona
  alias KlassHeroWeb.Theme

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 w-3 h-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :string, default: "w-4 h-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  @doc """
  Renders a gradient icon container.

  A circular or rounded container with gradient background and an icon or emoji inside.
  Commonly used throughout the application for visual consistency.

  ## Examples

      <.gradient_icon gradient_class={Theme.gradient(:cool)} size="lg">
        🎨
      </.gradient_icon>

      <.gradient_icon gradient_class={Theme.bg(:secondary)} size="md" shape="rounded">
        <.icon name="hero-user" class="w-5 h-5 text-white" />
      </.gradient_icon>
  """
  attr :gradient_class, :string,
    required: true,
    doc: "Tailwind gradient or solid background class"

  attr :size, :string, default: "md", values: ~w(sm md lg xl), doc: "Size of the icon container"

  attr :shape, :string,
    default: "circle",
    values: ~w(circle rounded),
    doc: "Shape of the container"

  attr :class, :string, default: "", doc: "Additional CSS classes"
  slot :inner_block, required: true, doc: "Icon content (emoji or heroicon)"

  def gradient_icon(assigns) do
    ~H"""
    <div class={[
      "flex items-center justify-center",
      size_classes(@size),
      shape_classes(@shape),
      @gradient_class,
      @class
    ]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp size_classes("sm"), do: "w-10 h-10 text-xl"
  defp size_classes("md"), do: "w-12 h-12 text-2xl"
  defp size_classes("lg"), do: "w-16 h-16 text-3xl"
  defp size_classes("xl"), do: "w-20 h-20 text-4xl lg:w-24 lg:h-24 lg:text-5xl"

  defp shape_classes("circle"), do: Theme.rounded(:full)
  defp shape_classes("rounded"), do: Theme.rounded(:lg)

  @doc """
  Renders a user avatar with a default emoticon.

  A circular container with gradient background and person emoji inside.
  Used for user avatars throughout the application when custom profile pictures
  are not available.

  ## Examples

      <.user_avatar size="sm" />
      <.user_avatar size="md" />
      <.user_avatar size="lg" ring={true} />
  """
  attr :size, :string, default: "md", values: ~w(sm md lg), doc: "Size of the avatar"
  attr :ring, :boolean, default: false, doc: "Whether to show a ring around the avatar"
  attr :class, :string, default: "", doc: "Additional CSS classes"

  def user_avatar(assigns) do
    ~H"""
    <div class={[
      "flex items-center justify-center bg-hero-blue-500",
      avatar_size_classes(@size),
      Theme.rounded(:full),
      @ring && "ring ring-hero-blue-500 ring-offset-2",
      @class
    ]}>
      <span class={avatar_emoji_classes(@size)}>👤</span>
    </div>
    """
  end

  defp avatar_size_classes("sm"), do: "w-10 h-10"
  defp avatar_size_classes("md"), do: "w-12 h-12"
  defp avatar_size_classes("lg"), do: "w-16 h-16"

  defp avatar_emoji_classes("sm"), do: "text-lg"
  defp avatar_emoji_classes("md"), do: "text-xl"
  defp avatar_emoji_classes("lg"), do: "text-2xl"

  @doc """
  Renders an account dropdown menu — gradient initial-circle trigger that opens
  a panel with the signed-in email, a Settings link, and a Log out action.

  Used in app chrome (parent + provider topbars). Marketing pages do not show
  this menu — signed-in users land on the marketing site with a single
  "Go to dashboard" CTA instead.

  The trigger mirrors the parent sidebar avatar styling so visual identity stays
  consistent across the parent surface. `id` must be unique per render — the
  panel and backdrop are toggled via `JS.toggle/1` keyed off this id, so two
  instances on the same page (desktop + mobile topbar) need distinct ids.

  ## Examples

      <.kh_user_menu user={@current_scope.user} id="parent-user-menu-desktop" />
  """
  attr :user, :map, required: true, doc: "Accounts.User struct (uses :name and :email)"

  attr :id, :string,
    required: true,
    doc: "Unique DOM id; required because two instances may live on one page"

  attr :class, :string, default: ""

  attr :personas, :list,
    default: [],
    doc:
      "Personas this account holds, as plain atoms. Not a Scope: this is a design-system primitive and must not know about Accounts."

  attr :active_persona, :atom, default: nil, doc: "The persona currently being viewed."

  def kh_user_menu(assigns) do
    ~H"""
    <div class={["relative", @class]}>
      <button
        type="button"
        id={"#{@id}-trigger"}
        aria-label={gettext("Open account menu")}
        aria-haspopup="menu"
        aria-expanded="false"
        aria-controls={"#{@id}-panel"}
        phx-click={
          Phoenix.LiveView.JS.toggle(to: "##{@id}-panel")
          |> Phoenix.LiveView.JS.toggle(to: "##{@id}-backdrop")
          |> Phoenix.LiveView.JS.toggle_attribute(
            {"aria-expanded", "true", "false"},
            to: "##{@id}-trigger"
          )
        }
        class="w-10 h-10 rounded-full bg-gradient-to-br from-hero-blue-400 to-hero-yellow-500 flex items-center justify-center font-bold text-black hover:shadow-md transition-shadow focus:outline-none focus-visible:ring-2 focus-visible:ring-[var(--brand-primary)] focus-visible:ring-offset-2"
      >
        {kh_user_menu_initial(@user)}
      </button>

      <div
        id={"#{@id}-backdrop"}
        phx-click={
          Phoenix.LiveView.JS.hide(to: "##{@id}-panel")
          |> Phoenix.LiveView.JS.hide(to: "##{@id}-backdrop")
          |> Phoenix.LiveView.JS.set_attribute({"aria-expanded", "false"}, to: "##{@id}-trigger")
        }
        class="hidden fixed inset-0 z-30"
        aria-hidden="true"
      >
      </div>

      <div
        id={"#{@id}-panel"}
        role="menu"
        aria-labelledby={"#{@id}-trigger"}
        class="hidden absolute right-0 top-full mt-2 w-64 bg-white rounded-xl border border-hero-grey-200 shadow-xl z-40 overflow-hidden"
      >
        <div class="px-4 py-3 border-b border-hero-grey-200 bg-hero-cream-100">
          <div class="text-xs text-hero-grey-600 font-semibold">{gettext("Signed in as")}</div>
          <div class="text-sm font-bold truncate">{@user.email}</div>
        </div>
        <.kh_menu_item href={~p"/users/settings"} icon="hero-cog-6-tooth">
          {gettext("Settings")}
        </.kh_menu_item>
        <.persona_switcher personas={@personas} active_persona={@active_persona} />
        <.admin_nav is_admin={Map.get(@user, :is_admin, false)} />
        <.kh_menu_item
          href={~p"/users/log-out"}
          method="delete"
          icon="hero-arrow-right-on-rectangle"
          variant={:destructive}
          class="border-t border-hero-grey-200"
        >
          {gettext("Log out")}
        </.kh_menu_item>
      </div>
    </div>
    """
  end

  @doc """
  Renders an item inside a `kh_user_menu/1` panel — icon + label, with optional
  `:destructive` variant (red palette, used for logout-style actions). Accepts
  the same `href` / `navigate` / `method` routing attrs as `<.link>`.
  """
  attr :href, :string, default: nil
  attr :navigate, :string, default: nil
  attr :method, :string, default: nil
  attr :icon, :string, required: true, doc: "Heroicon name (e.g. \"hero-cog-6-tooth\")"

  attr :variant, :atom,
    default: :default,
    values: [:default, :destructive],
    doc: "`:destructive` swaps the color palette for logout-style actions"

  attr :class, :string, default: ""
  slot :inner_block, required: true

  def kh_menu_item(assigns) do
    ~H"""
    <.link
      href={@href}
      navigate={@navigate}
      method={@method}
      role="menuitem"
      class={[
        "flex items-center gap-2 px-4 py-2.5 text-sm font-semibold no-underline",
        kh_menu_item_variant_classes(@variant),
        @class
      ]}
    >
      <.icon name={@icon} class="w-4 h-4" /> {render_slot(@inner_block)}
    </.link>
    """
  end

  defp kh_menu_item_variant_classes(:default), do: "text-hero-black-100 hover:bg-hero-cream-100"
  defp kh_menu_item_variant_classes(:destructive), do: "text-red-600 hover:bg-red-50"

  @doc """
  Renders the admin section of a `kh_user_menu/1` panel. Renders nothing when
  `is_admin` is false.
  """
  attr :is_admin, :boolean, default: false

  def admin_nav(assigns) do
    ~H"""
    <div :if={@is_admin} class="border-t border-hero-grey-200">
      <div class="px-4 py-2 bg-hero-cream-100">
        <div class="text-xs text-hero-grey-600 font-semibold uppercase tracking-wider">
          {gettext("Admin")}
        </div>
      </div>
      <.kh_menu_item navigate={~p"/admin/accounts"} icon="hero-chart-bar-square">
        {gettext("Dashboard")}
      </.kh_menu_item>
      <.kh_menu_item navigate={~p"/admin/verifications"} icon="hero-shield-check">
        {gettext("Verifications")}
      </.kh_menu_item>
    </div>
    """
  end

  @doc """
  Switches which persona's surface you are looking at (#899).

  Renders nothing for an account holding a single persona, which is almost every
  account: there is nothing to switch between, and a control that only ever names
  your own one role is noise.

  Each entry POSTs. Only the plug pipeline can write the session, so a LiveView
  event could not make the switch survive the next request (#1161). The chrome is
  its own confirmation — the parent surface is white-with-blue and the provider
  surface black-with-yellow — so the switch is visible before any copy is read.
  """
  attr :personas, :list, default: []
  attr :active_persona, :atom, default: nil

  def persona_switcher(assigns) do
    ~H"""
    <div :if={length(@personas) > 1} class="border-t border-hero-grey-200">
      <div class="px-4 py-2 bg-hero-cream-100">
        <div class="text-xs text-hero-grey-600 font-semibold uppercase tracking-wider">
          {gettext("Viewing as %{persona}", persona: Persona.label(@active_persona))}
        </div>
      </div>
      <.kh_menu_item
        :for={persona <- @personas -- [@active_persona]}
        href={~p"/users/persona/#{persona}"}
        method="post"
        icon="hero-arrows-right-left"
      >
        {gettext("Switch to %{persona}", persona: Persona.label(persona))}
      </.kh_menu_item>
    </div>
    """
  end

  defp kh_user_menu_initial(user) do
    (user.name || user.email || "?")
    |> String.first()
    |> String.upcase()
  end

  @doc """
  Renders a status pill/badge.

  Small colored pill with text, used for status indicators, tags, and labels.

  ## Examples

      <.status_pill color="success">5 spots left</.status_pill>
      <.status_pill color="warning">2 spots left</.status_pill>
      <.status_pill color="error">Full</.status_pill>
      <.status_pill color="info">Available</.status_pill>
      <.status_pill color="custom" class="bg-blue-100 text-blue-700">Today</.status_pill>
  """
  attr :color, :string, default: "info", values: ~w(success warning error info custom)
  attr :class, :string, default: "", doc: "Additional CSS classes (required when color='custom')"
  slot :inner_block, required: true

  def status_pill(assigns) do
    ~H"""
    <span class={[
      "px-2 py-1 text-xs font-medium",
      Theme.rounded(:full),
      color_classes(@color),
      @class
    ]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp color_classes("success"), do: "bg-green-100 text-green-700"
  defp color_classes("warning"), do: "bg-orange-100 text-orange-700"
  defp color_classes("error"), do: "bg-red-100 text-red-700"
  defp color_classes("info"), do: "bg-blue-100 text-blue-700"
  defp color_classes("custom"), do: ""

  @doc """
  Renders a section label badge with gradient background.

  Used as a category marker above section headings (e.g. "For Families", "For Providers").

  ## Examples

      <.section_label>For Families</.section_label>
      <.section_label gradient={:safety}>Special</.section_label>
  """
  attr :gradient, :atom, default: :primary, doc: "Theme gradient name"
  slot :inner_block, required: true

  def section_label(assigns) do
    ~H"""
    <span class={[
      "inline-block px-4 py-1.5 text-sm font-medium",
      Theme.gradient(@gradient),
      "text-white",
      Theme.rounded(:full)
    ]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  @doc """
  Renders a progress bar with label and percentage.

  ## Examples

      <.progress_bar label="Progress" percentage={80} color_class={Theme.bg(:primary)} />
      <.progress_bar label="Completion" percentage={65} color_class="bg-green-500" />
  """
  attr :label, :string, default: "Progress"
  attr :percentage, :integer, required: true, doc: "Progress percentage (0-100)"

  attr :color_class, :string,
    default: Theme.bg(:primary),
    doc: "Tailwind background color class for the progress bar"

  attr :class, :string, default: ""

  def progress_bar(assigns) do
    ~H"""
    <div class={@class}>
      <div class={["flex justify-between text-xs mb-1", Theme.text_color(:secondary)]}>
        <span>{@label}</span>
        <span>{@percentage}%</span>
      </div>
      <div class={["w-full h-2", Theme.rounded(:full), Theme.bg(:medium)]}>
        <div
          class={[@color_class, "h-2", Theme.transition(:slow), Theme.rounded(:full)]}
          style={"width: #{@percentage}%"}
        >
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a circular back button with glassmorphism effect.

  Automatically uses browser back navigation when no custom click handler is provided.

  ## Examples

      <.back_button />  # Uses browser back navigation
      <.back_button on_click="back_to_programs" />  # Custom event handler
      <.back_button phx-click="go_back" class="ml-4" />  # Custom event handler
      <.back_button size={:lg} color="text-blue-600" />  # Large button with custom color
  """
  attr :size, :atom, default: :md, values: [:sm, :md, :lg], doc: "Button and icon size"
  attr :color, :string, default: "text-hero-grey-600", doc: "Icon color class"

  attr :use_browser_back, :boolean,
    default: true,
    doc: "Use browser back navigation when no phx-click provided"

  attr :on_click, :string, default: nil, doc: "Phoenix event name (deprecated, use phx-click)"
  attr :class, :string, default: ""
  attr :rest, :global, include: ~w(phx-click phx-value-* disabled)

  def back_button(assigns) do
    assigns = assign(assigns, :size_classes, back_button_size_classes(assigns.size))

    assigns =
      if assigns.use_browser_back && !assigns.rest[:"phx-click"] && !assigns.on_click do
        assigns
        |> assign(:use_browser_back_nav, true)
      else
        assigns =
          if assigns.on_click && !assigns.rest[:"phx-click"] do
            Map.put(assigns, :rest, Map.put(assigns.rest, :"phx-click", assigns.on_click))
          else
            assigns
          end

        assigns
        |> assign(:use_browser_back_nav, false)
      end

    ~H"""
    <button
      type="button"
      class={[
        @size_classes.padding,
        "bg-white shadow-sm",
        Theme.rounded(:full),
        "hover:bg-hero-grey-50",
        Theme.transition(:normal),
        @class
      ]}
      onclick={if @use_browser_back_nav, do: "window.history.back(); return false;", else: nil}
      {@rest}
    >
      <.icon name="hero-arrow-left" class={"#{@size_classes.icon} #{@color}"} />
    </button>
    """
  end

  defp back_button_size_classes(:sm), do: %{icon: "w-4 h-4", padding: "p-1"}
  defp back_button_size_classes(:md), do: %{icon: "w-6 h-6", padding: "p-2"}
  defp back_button_size_classes(:lg), do: %{icon: "w-8 h-8", padding: "p-3"}

  @doc """
  Renders a section divider with centered text.

  Commonly used in forms to separate sections like "Or continue with".

  ## Examples

      <.section_divider text="Or continue with" />
      <.section_divider text="Or sign up with" class="my-6" />
      <.section_divider text="Or continue with" bg_color="bg-transparent" text_color="text-white/80" line_color="border-white/20" />
  """
  attr :text, :string, required: true
  attr :class, :string, default: ""

  attr :bg_color, :string,
    default: Theme.bg(:surface),
    doc: "Tailwind background color class for text background"

  attr :text_color, :string, default: Theme.text_color(:muted), doc: "Tailwind text color class"

  attr :line_color, :string,
    default: Theme.border_color(:light),
    doc: "Tailwind border color class"

  def section_divider(assigns) do
    ~H"""
    <div class={["relative", @class]}>
      <div class="absolute inset-0 flex items-center">
        <div class={["w-full border-t", @line_color]}></div>
      </div>
      <div class="relative flex justify-center text-sm">
        <span class={["px-2", @bg_color, @text_color]}>{@text}</span>
      </div>
    </div>
    """
  end

  @doc """
  Renders a social login/signup button with provider icon.

  ## Examples

      <.social_button provider="google" on_click="social_login" />
      <.social_button provider="facebook" phx-click="social_signup" />
  """
  attr :provider, :string, required: true, values: ~w(google facebook)
  attr :on_click, :string, default: nil, doc: "Phoenix event name (deprecated, use phx-click)"
  attr :variant, :string, default: "light", values: ~w(light dark)
  attr :class, :string, default: ""
  attr :rest, :global, include: ~w(phx-click phx-value-* disabled)

  def social_button(assigns) do
    assigns =
      if assigns.on_click && !assigns.rest[:"phx-click"] do
        Map.put(assigns, :rest, Map.put(assigns.rest, :"phx-click", assigns.on_click))
      else
        assigns
      end

    ~H"""
    <button
      type="button"
      class={[
        "flex justify-center items-center px-4 py-3",
        Theme.transition(:normal),
        Theme.rounded(:lg),
        button_variant_classes(@variant),
        @class
      ]}
      {@rest}
    >
      <%= if @provider == "google" do %>
        <svg class="w-5 h-5" viewBox="0 0 24 24" fill="currentColor">
          <path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" />
          <path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" />
          <path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" />
          <path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" />
        </svg>
      <% end %>
      <%= if @provider == "facebook" do %>
        <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
          <path d="M24 12.073c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.99 4.388 10.954 10.125 11.854v-8.385H7.078v-3.47h3.047V9.43c0-3.007 1.792-4.669 4.533-4.669 1.312 0 2.686.235 2.686.235v2.953H15.83c-1.491 0-1.956.925-1.956 1.874v2.25h3.328l-.532 3.47h-2.796v8.385C19.612 23.027 24 18.062 24 12.073z" />
        </svg>
      <% end %>
    </button>
    """
  end

  defp button_variant_classes("light") do
    [
      "border",
      Theme.border_color(:medium),
      Theme.text_color(:body),
      "hover:#{Theme.bg(:muted)}"
    ]
    |> Enum.join(" ")
  end

  defp button_variant_classes("dark") do
    "bg-white/10 border border-white/20 text-white hover:bg-white/20"
  end

  @doc """
  Renders an email icon for input fields.

  ## Examples

      <.email_icon color="text-white/60" />
      <.email_icon color={Theme.text_color(:subtle)} />
  """
  attr :color, :string, default: Theme.text_color(:subtle)
  attr :class, :string, default: ""

  def email_icon(assigns) do
    ~H"""
    <svg
      class={["w-5 h-5", @color, @class]}
      fill="none"
      stroke="currentColor"
      viewBox="0 0 24 24"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="2"
        d="M16 12a4 4 0 10-8 0 4 4 0 008 0zm0 0v1.5a2.5 2.5 0 005 0V12a9 9 0 10-9 9m4.5-1.206a8.959 8.959 0 01-4.5 1.207"
      >
      </path>
    </svg>
    """
  end

  @doc """
  Renders a password/eye icon for password input fields.

  ## Examples

      <.password_icon color="text-white/60" />
      <.password_icon color={Theme.text_color(:subtle)} />
  """
  attr :color, :string, default: Theme.text_color(:subtle)
  attr :class, :string, default: ""

  def password_icon(assigns) do
    ~H"""
    <svg
      class={["w-5 h-5", @color, @class]}
      fill="none"
      stroke="currentColor"
      viewBox="0 0 24 24"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="2"
        d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
      >
      </path>
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="2"
        d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"
      >
      </path>
    </svg>
    """
  end

  @doc """
  Renders an error alert box with icon and error messages.

  ## Examples

      <.error_alert errors={["Invalid email", "Password too short"]} />
      <.error_alert errors={@errors} />
  """
  attr :errors, :list, required: true
  attr :class, :string, default: ""

  def error_alert(assigns) do
    ~H"""
    <div
      :if={@errors != []}
      class={["mb-6 p-4 bg-red-50 border border-red-200", Theme.rounded(:md), @class]}
    >
      <div class="flex">
        <svg
          class="w-5 h-5 text-red-400"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
          >
          </path>
        </svg>
        <div class="ml-3">
          <p :for={error <- @errors} class="text-sm text-red-700">{error}</p>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a statistic display with large gradient number and label.

  ## Examples

      <.stat_display
        value="10,000+"
        label="Active Families"
        gradient_class={Theme.gradient(:primary)}
      />
  """
  attr :value, :string, required: true
  attr :label, :string, required: true
  attr :gradient_class, :string, required: true
  attr :class, :string, default: ""

  def stat_display(assigns) do
    ~H"""
    <div class={["text-center", @class]}>
      <div class={[
        Theme.typography(:hero),
        "bg-clip-text text-transparent mb-2",
        @gradient_class
      ]}>
        {@value}
      </div>
      <div class={Theme.text_color(:secondary)}>{@label}</div>
    </div>
    """
  end

  @doc """
  Renders an empty state with icon, title, description, and optional action.

  Displays a centered empty state with gray icon circle, title, and description.
  Commonly used when no results are found or when a list is empty.

  ## Examples

      <.empty_state
        icon="hero-magnifying-glass"
        title="No programs found"
        description="Try adjusting your search or filter criteria."
      />

      <.empty_state
        icon="hero-calendar"
        title="No sessions scheduled"
        description="You have no sessions scheduled for today."
      />

      <.empty_state icon="hero-clipboard-document-list" title="No records yet">
        Your children's participation will appear here
      </.empty_state>

      <.empty_state
        icon="hero-plus"
        title="No items yet"
        description="Get started by adding your first item."
      >
        <:action>
          <button class={["mt-4 px-4 py-2 bg-hero-blue-400 text-white", Theme.rounded(:md)]}>
            Add Item
          </button>
        </:action>
      </.empty_state>
  """
  attr :icon, :string, required: true, doc: "Heroicon name (e.g., 'hero-calendar')"
  attr :title, :string, required: true
  attr :description, :string, default: nil, doc: "Static description text"
  attr :class, :string, default: ""
  attr :data_testid, :string, default: "empty-state", doc: "Test ID for testing"
  attr :rest, :global, doc: "Additional HTML attributes"
  slot :inner_block, doc: "Optional dynamic description content (overrides description attr)"
  slot :action, doc: "Optional action button or link"

  def empty_state(assigns) do
    ~H"""
    <div data-testid={@data_testid} class={["text-center py-12", @class]} {@rest}>
      <div class={[
        "w-16 h-16 flex items-center justify-center mx-auto mb-4",
        Theme.rounded(:full),
        "bg-hero-blue-50"
      ]}>
        <.icon name={@icon} class="w-8 h-8 text-hero-blue-400" />
      </div>
      <h3 class={[Theme.typography(:card_title), "mb-2", Theme.text_color(:heading)]}>{@title}</h3>
      <p class={Theme.text_color(:secondary)}>
        <%= if @inner_block != [] do %>
          {render_slot(@inner_block)}
        <% else %>
          {@description}
        <% end %>
      </p>
      <div :if={@action != []}>
        {render_slot(@action)}
      </div>
    </div>
    """
  end

  @doc """
  Renders a skeleton placeholder card with pulsing animation.

  Mimics the layout of a program card to show during loading states.
  Uses `animate-pulse` for a subtle breathing effect.

  ## Examples

      <.skeleton_card />

      <div class="grid md:grid-cols-3 gap-6">
        <.skeleton_card :for={_ <- 1..3} />
      </div>
  """
  attr :class, :string, default: ""

  def skeleton_card(assigns) do
    ~H"""
    <div class={[
      "animate-pulse bg-white overflow-hidden shadow-sm border border-hero-grey-100",
      Theme.rounded(:xl),
      @class
    ]}>
      <div class="h-48 bg-hero-grey-200"></div>
      <div class="p-6 space-y-3">
        <div class="h-5 bg-hero-grey-200 rounded w-3/4"></div>
        <div class="h-4 bg-hero-grey-100 rounded w-full"></div>
        <div class="h-4 bg-hero-grey-100 rounded w-2/3"></div>
        <div class="space-y-2 pt-2">
          <div class="h-3 bg-hero-grey-100 rounded w-1/2"></div>
          <div class="h-3 bg-hero-grey-100 rounded w-2/5"></div>
        </div>
        <div class="pt-4 border-t border-hero-grey-100">
          <div class="h-5 bg-hero-grey-200 rounded w-1/3"></div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a circular icon button with hover effects.

  Small, circular button with an icon, commonly used for actions like favorite,
  menu, close, etc. Supports different background variants.

  ## Examples

      <.icon_button icon_path="M6 18L18 6M6 6l12 12" aria_label="Close" phx-click="close" />

      <.icon_button
        icon_path="M12 5v.01M12 12v.01M12 19v.01M12 6a1 1 0 110-2..."
        variant="light"
        phx-click="open_menu"
      />

      <.icon_button
        icon_path="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364..."
        variant="glass"
        class="text-red-500"
        phx-click="toggle_favorite"
      />
  """
  attr :icon_path, :string, required: true, doc: "SVG path data for the icon"

  attr :variant, :string,
    default: "light",
    values: ~w(light glass solid),
    doc: "Button background style"

  attr :aria_label, :string, default: nil, doc: "Accessibility label"
  attr :class, :string, default: ""
  attr :rest, :global, include: ~w(phx-click phx-value-* disabled type)

  def icon_button(assigns) do
    ~H"""
    <button
      type="button"
      aria-label={@aria_label}
      class={[
        "p-2",
        Theme.transition(:normal),
        Theme.rounded(:full),
        icon_button_variant(@variant),
        @class
      ]}
      {@rest}
    >
      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d={@icon_path}
        >
        </path>
      </svg>
    </button>
    """
  end

  defp icon_button_variant("light"), do: "#{Theme.bg(:light)} hover:#{Theme.bg(:medium)}"

  defp icon_button_variant("glass"), do: "#{Theme.bg(:surface)}/80 backdrop-blur-sm hover:#{Theme.bg(:surface)}"

  defp icon_button_variant("solid"), do: "#{Theme.bg(:surface)} hover:#{Theme.bg(:muted)} shadow-sm"

  @doc """
  Renders a unified page header with support for multiple layouts and styles.

  This component consolidates various header patterns used across LiveViews,
  providing consistent spacing, typography, and responsive behavior.

  ## Variants
  - `:white` - White background with dark text (default)
  - `:gradient` - Gradient background with white text

  ## Examples

      # Simple white header with title
      <.page_header>
        <:title>Programs</:title>
      </.page_header>

      # Gradient header with title and subtitle
      <.page_header variant={:gradient}>
        <:title>Settings</:title>
        <:subtitle>Manage your account and preferences</:subtitle>
      </.page_header>

      # Header with profile section (Dashboard)
      <.page_header variant={:gradient} rounded>
        <:profile>
          <.user_avatar size="md" />
          <div>
            <h2 class={Theme.typography(:card_title)}>{@user.name}</h2>
            <p class={[Theme.typography(:body_small), "text-white/80"]}>{length(@children)} children enrolled</p>
          </div>
        </:profile>
        <:actions>
          <button>Settings</button>
        </:actions>
      </.page_header>

      # Header with back button
      <.page_header variant={:gradient} show_back_button>
        <:title>Enrollment</:title>
      </.page_header>

      # Header with action buttons
      <.page_header>
        <:title>Programs</:title>
        <:actions>
          <button class="p-2">More options</button>
        </:actions>
      </.page_header>
  """
  attr :variant, :atom, default: :white, values: [:white, :gradient, :dark, :peach]

  attr :gradient_class, :string, default: Theme.gradient(:primary)

  attr :rounded, :boolean, default: false, doc: "Apply rounded-b-3xl style for Dashboard"
  attr :show_back_button, :boolean, default: false
  attr :centered, :boolean, default: false, doc: "Center-align content (for hero-style headers)"

  attr :size, :atom,
    default: :normal,
    values: [:normal, :large],
    doc: "Padding size - :large for hero sections"

  attr :container_class, :string,
    default: nil,
    doc: "Custom container class (e.g., max-w-4xl mx-auto)"

  attr :class, :string, default: nil
  attr :rest, :global

  slot :title, doc: "Main header title (required unless using :profile slot)"
  slot :subtitle
  slot :profile, doc: "Profile section with avatar and user info (alternative to :title)"
  slot :actions, doc: "Action buttons (settings, notifications, more options)"
  slot :inner_block, doc: "Additional content below title (search bars, tags, etc.)"

  def page_header(assigns) do
    ~H"""
    <div class={[
      @size == :normal && "p-6",
      @size == :large && "py-16 lg:py-24 px-4 sm:px-6 lg:px-8",
      @variant == :gradient && [@gradient_class, "text-white"],
      @variant == :dark && "bg-hero-black text-white",
      @variant == :peach && "bg-hero-pink-50",
      @variant == :white && "#{Theme.bg(:surface)} shadow-sm",
      @rounded && "rounded-b-3xl",
      @class
    ]}>
      <div class={[@container_class]}>
        <%= if @profile != [] and @title == [] do %>
          <div class="flex items-center justify-between">
            <div class="flex items-center space-x-4">
              {render_slot(@profile)}
            </div>

            <div :if={@actions != []} class="flex space-x-2">
              {render_slot(@actions)}
            </div>
          </div>
        <% else %>
          <div class={[
            @centered && "text-center",
            !@centered && "flex items-center justify-between mb-4"
          ]}>
            <div class={[
              @centered && "mx-auto",
              !@centered && "flex items-center gap-4"
            ]}>
              <.back_button :if={@show_back_button && !@centered} {@rest} />
              <div>
                <h1 class={[
                  @centered && Theme.typography(:page_title),
                  !@centered && Theme.typography(:section_title),
                  @variant in [:white, :peach] && Theme.text_color(:heading),
                  @variant in [:gradient, :dark] && "text-white"
                ]}>
                  {render_slot(@title)}
                </h1>
                <p
                  :if={@subtitle != []}
                  class={[
                    "mt-1",
                    @centered && "text-xl max-w-3xl mx-auto",
                    !@centered && "text-sm",
                    @variant in [:white, :peach] && Theme.text_color(:secondary),
                    @variant in [:gradient, :dark] && "text-white/80"
                  ]}
                >
                  {render_slot(@subtitle)}
                </p>
              </div>
            </div>

            <div :if={@actions != [] && !@centered} class="flex space-x-2">
              {render_slot(@actions)}
            </div>
          </div>

          <div :if={@inner_block != []} class={[@centered && "max-w-7xl mx-auto mt-6"]}>
            {render_slot(@inner_block)}
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @doc """
  Renders a generic card container with flexible content slots.

  This is a foundational component for creating consistent card layouts throughout
  the application. Use slots for maximum flexibility in card content composition.

  ## Examples

      # Simple card with body only
      <.card>
        <:body>
          <p>Card content here</p>
        </:body>
      </.card>

      # Card with header, body, and footer
      <.card variant={:elevated}>
        <:header>
          <h3>Card Title</h3>
        </:header>
        <:body>
          <p>Main content here</p>
        </:body>
        <:footer>
          <button>Action</button>
        </:footer>
      </.card>

      # Clickable card with custom padding
      <.card padding="p-4" phx-click="select_item" phx-value-id={@item.id}>
        <:body>
          <p>Clickable content</p>
        </:body>
      </.card>
  """
  attr :variant, :atom, default: :default, values: [:default, :elevated, :outlined]
  attr :padding, :string, default: "p-6"
  attr :class, :string, default: ""
  slot :header
  slot :body, required: true
  slot :footer
  attr :rest, :global, include: ~w(phx-click phx-value-*)

  def card(assigns) do
    ~H"""
    <div
      class={[
        Theme.bg(:surface),
        Theme.rounded(:xl),
        card_variant_classes(@variant),
        @padding,
        @class
      ]}
      {@rest}
    >
      <div :if={@header != []} class={["border-b pb-4 mb-4", Theme.border_color(:light)]}>
        {render_slot(@header)}
      </div>

      <div>
        {render_slot(@body)}
      </div>

      <div :if={@footer != []} class={["border-t pt-4 mt-4", Theme.border_color(:light)]}>
        {render_slot(@footer)}
      </div>
    </div>
    """
  end

  defp card_variant_classes(:default), do: "shadow-sm border #{Theme.border_color(:light)}"
  defp card_variant_classes(:elevated), do: "shadow-lg"
  defp card_variant_classes(:outlined), do: "border-2 #{Theme.border_color(:medium)}"

  @doc """
  Renders a styled date selector with label and form wrapper.

  Commonly used for date-based filtering in lists and streams. Automatically
  handles date formatting for the HTML date input.

  The wrapping form is given `"<id>-form"`. That id is what the client uses to recover the
  form after a reconnect, so it is load-bearing, not decorative — without it the selected
  date silently reverts to the mount default when the socket drops.

  ## Examples

      <.date_selector
        id="session-date"
        name="date"
        value={@selected_date}
        label="Select Date:"
        phx_change="change_date"
      />

      <.date_selector
        id="filter-date"
        name="filter_date"
        value={@filter_date}
      />
  """
  attr :id, :string, required: true, doc: "Input element ID; the wrapping form gets `<id>-form`"
  attr :name, :string, required: true, doc: "Form field name"
  attr :value, :any, default: nil, doc: "Current date value (Date or ISO8601 string)"
  attr :label, :string, default: nil, doc: "Optional label text"
  attr :phx_change, :string, default: nil, doc: "Change event name"
  attr :class, :string, default: "", doc: "Additional container classes"
  attr :rest, :global, doc: "Additional HTML attributes for the input"

  def date_selector(assigns) do
    ~H"""
    <form
      id={"#{@id}-form"}
      phx-change={@phx_change}
      class={["flex flex-col sm:flex-row gap-4 items-start sm:items-center", @class]}
    >
      <label :if={@label} for={@id} class="text-sm font-medium text-gray-700">
        {@label}
      </label>
      <input
        type="date"
        id={@id}
        name={@name}
        value={format_date_value(@value)}
        class={[
          "px-4 py-2 border border-gray-300 focus:outline-none focus:ring-2 focus:ring-hero-blue-500 focus:border-transparent",
          Theme.rounded(:lg),
          Theme.transition(:normal)
        ]}
        {@rest}
      />
    </form>
    """
  end

  defp format_date_value(nil), do: nil
  defp format_date_value(%Date{} = date), do: Date.to_iso8601(date)
  defp format_date_value(value) when is_binary(value), do: value

  @doc """
  Renders a pricing tier card with features list and CTA button.

  Displays pricing information with optional "Most Popular" badge, feature list with
  checkmarks, and call-to-action button. Supports both default and popular variants.

  ## Examples

      <.pricing_card
        title="Explorer Family"
        subtitle="Perfect for trying out Klass Hero"
        price="Free"
        period="forever"
        features={["Browse all programs", "2 bookings per month", "Read reviews", "Join community"]}
        cta_text="Start Exploring"
        phx-click="select_plan"
        phx-value-plan="explorer"
      />

      <.pricing_card
        title="Active Family"
        subtitle="For families who love activities"
        price="€8"
        period="month"
        features={["AI Support Bot", "Unlimited bookings", "Progress tracking", "Direct messaging", "1 free cancellation/month"]}
        popular
        cta_text="Get Started"
        phx-click="select_plan"
        phx-value-plan="active"
      />
  """
  attr :title, :string, required: true, doc: "Plan name (e.g., 'Explorer Family')"
  attr :subtitle, :string, default: nil, doc: "Plan description subtitle"
  attr :price, :string, required: true, doc: "Price text (e.g., 'Free', '€8')"
  attr :period, :string, default: "forever", doc: "Billing period (e.g., 'forever', 'month')"
  attr :features, :list, required: true, doc: "List of feature strings"
  attr :popular, :boolean, default: false, doc: "Show 'Most Popular' badge"
  attr :cta_text, :string, default: "Start Exploring", doc: "Button text"
  attr :class, :string, default: ""
  attr :rest, :global, include: ~w(phx-click phx-value-*)

  def pricing_card(assigns) do
    ~H"""
    <div class={[
      "relative",
      Theme.bg(:surface),
      Theme.rounded(:xl),
      "border p-6",
      @popular && "border-2 border-hero-blue-500 shadow-lg transform scale-105",
      !@popular && ["border", Theme.border_color(:light), "shadow-sm"],
      Theme.transition(:normal),
      @class
    ]}>
      <div
        :if={@popular}
        class={[
          "absolute -top-3 left-1/2 transform -translate-x-1/2 px-4 py-1",
          Theme.rounded(:full),
          Theme.gradient(:primary),
          "text-white text-sm font-semibold"
        ]}
      >
        Most Popular
      </div>

      <div class="mb-6">
        <h3 class={[Theme.typography(:card_title), "mb-1", Theme.text_color(:heading)]}>
          {@title}
        </h3>
        <p :if={@subtitle} class={["text-sm", Theme.text_color(:muted)]}>
          {@subtitle}
        </p>
      </div>

      <div class="mb-6">
        <div class="flex items-baseline gap-1">
          <span class={[Theme.typography(:section_title), Theme.text_color(:heading)]}>
            {@price}
          </span>
          <span class={["text-sm", Theme.text_color(:muted)]}>
            / {@period}
          </span>
        </div>
      </div>

      <ul class="space-y-3 mb-6">
        <li :for={feature <- @features} class="flex items-start gap-2">
          <.icon name="hero-check-circle" class="w-5 h-5 flex-shrink-0 mt-0.5 text-hero-blue-600" />
          <span class={["text-sm", Theme.text_color(:body)]}>{feature}</span>
        </li>
      </ul>

      <button
        class={[
          "w-full py-3 font-semibold",
          Theme.rounded(:lg),
          @popular && [Theme.gradient(:primary), "text-white hover:shadow-lg"],
          !@popular &&
            [
              Theme.bg(:primary),
              "text-white",
              "hover:#{Theme.bg(:primary)}/90"
            ],
          Theme.transition(:normal)
        ]}
        {@rest}
      >
        {@cta_text}
      </button>
    </div>
    """
  end

  @doc """
  Renders a messages notification indicator with unread badge.

  A circular button with a chat icon that links to the messages page.
  Shows an unread count badge when there are unread messages.

  ## Examples

      <.messages_indicator unread_count={5} />
      <.messages_indicator unread_count={0} />
      <.messages_indicator unread_count={3} href={~p"/provider/messages"} />

  """
  attr :unread_count, :integer, default: 0
  attr :href, :string, default: nil
  attr :class, :string, default: ""

  def messages_indicator(assigns) do
    assigns = assign(assigns, :href, assigns[:href] || ~p"/messages")

    ~H"""
    <.link navigate={@href} class={["relative btn btn-ghost btn-circle", @class]}>
      <.icon name="hero-chat-bubble-left-right" class="w-6 h-6 text-hero-grey-600" />
      <span
        :if={@unread_count > 0}
        class="absolute -top-1 -right-1 min-w-5 h-5 px-1 text-xs font-semibold text-error-content bg-error rounded-full flex items-center justify-center"
      >
        {min(@unread_count, 99)}
      </span>
    </.link>
    """
  end

  @doc """
  Renders a collapsible FAQ accordion item.

  Interactive FAQ item with smooth expand/collapse transitions using Phoenix LiveView JS.
  The chevron icon rotates 180 degrees when expanded. Handles all interaction client-side
  without server round-trips.

  ## Examples

      <.faq_item
        id="faq-1"
        question="How does the 6-step provider vetting process work?"
        answer="Every provider completes identity and age verification, experience validation, an extended background check, video screening, child safeguarding training, and agreement to our Community Guidelines before being approved."
      />

      <.faq_item
        id="faq-2"
        question="How do parents discover programs on Klass Hero?"
        answer="Browse by neighborhood, age range, activity type, or schedule. Every listing shows the provider's verification status, parent reviews, and live availability."
        expanded
      />

      <.faq_item
        id="faq-3"
        question="Where is Klass Hero available?"
        answer="Currently serving Berlin, with expansion to other German cities coming soon."
        class="mb-4"
      />
  """
  attr :id, :string, required: true, doc: "Unique ID for JS targeting (e.g., 'faq-1')"
  attr :question, :string, required: true, doc: "FAQ question text"

  attr :answer, :string,
    default: nil,
    doc: "FAQ answer text (use inner_block slot for rich content)"

  attr :expanded, :boolean, default: false, doc: "Initial expanded state"
  attr :class, :string, default: ""
  slot :inner_block, doc: "Optional rich HTML answer content; overrides :answer when provided"

  def faq_item(assigns) do
    ~H"""
    <div class={["border-b", Theme.border_color(:light), @class]}>
      <button
        type="button"
        class={[
          "w-full py-4 flex items-center justify-between text-left",
          "hover:bg-hero-grey-50",
          Theme.transition(:fast)
        ]}
        phx-click={
          Phoenix.LiveView.JS.toggle(to: "##{@id}-answer")
          |> Phoenix.LiveView.JS.toggle_class("rotate-180", to: "##{@id}-chevron")
        }
      >
        <span class={[Theme.typography(:card_title), Theme.text_color(:heading)]}>
          {@question}
        </span>
        <span
          id={"#{@id}-chevron"}
          class={[
            "w-5 h-5 flex-shrink-0 ml-4",
            Theme.text_color(:secondary),
            Theme.transition(:fast),
            @expanded && "rotate-180"
          ]}
        >
          <.icon name="hero-chevron-down" class="w-5 h-5" />
        </span>
      </button>
      <div
        id={"#{@id}-answer"}
        class={[
          "overflow-hidden",
          Theme.transition(:fast),
          @expanded == false && "hidden"
        ]}
      >
        <%= if @inner_block != [] do %>
          <div class={["pb-4 pr-12", Theme.text_color(:secondary)]}>
            {render_slot(@inner_block)}
          </div>
        <% else %>
          <p class={["pb-4 pr-12", Theme.text_color(:secondary)]}>
            {@answer}
          </p>
        <% end %>
      </div>
    </div>
    """
  end

  # Kh* primitives mirror `design_handoff/shared/Primitives.jsx` and consume
  # the semantic CSS variables in `assets/css/app.css` (--brand-*, --bg-*, etc.).

  @doc """
  Renders the Klass Hero brand logo.

  ## Examples

      <.kh_logo />
      <.kh_logo size={26} variant={:white} class="shrink-0" />
  """
  attr :size, :integer, default: 32, doc: "Logo height in pixels"
  attr :variant, :atom, default: :primary, values: [:primary, :white]
  attr :class, :string, default: ""
  attr :rest, :global

  def kh_logo(assigns) do
    ~H"""
    <img
      src={kh_logo_src(@variant)}
      alt="Klass Hero"
      height={@size}
      style={"height: #{@size}px; width: auto;"}
      class={["object-contain", @class]}
      {@rest}
    />
    """
  end

  defp kh_logo_src(:white), do: "/images/logo-white-large.png"
  defp kh_logo_src(_), do: "/images/logo.png"

  @doc """
  Renders a Klass Hero button.

  Maps to bundle's `KhButton` (Primitives.jsx:72). Variants map to brand-vocabulary
  CSS variables; sizes scale border-radius and padding together.

  ## Examples

      <.kh_button>Continue</.kh_button>
      <.kh_button variant={:dark} size={:lg} icon="hero-plus" phx-click="add">
        New program
      </.kh_button>
  """
  attr :variant, :atom,
    default: :primary,
    values: [:primary, :secondary, :ghost, :dark, :yellow]

  attr :size, :atom, default: :md, values: [:sm, :md, :lg]
  attr :icon, :string, default: nil, doc: "Heroicon name rendered before children"
  attr :type, :string, default: "button"
  attr :class, :string, default: ""

  attr :rest, :global,
    include: ~w(disabled form name value navigate patch href phx-click phx-submit phx-disable-with phx-target)

  slot :inner_block, required: true

  def kh_button(assigns) do
    ~H"""
    <button
      type={@type}
      class={
        [
          # No `border-0` here: Tailwind preflight already zeroes borders on every element, and an
          # explicit `border-0` in this base stack out-cascades the `:ghost` variant's opt-in `border`
          # (equal-specificity single-class rules resolve by emit order, not markup order), leaving the
          # ghost button invisible at rest. Borderless variants stay borderless via preflight.
          # typography-lint-ignore: KhButton owns its own display-font CTA styling (size scales separately)
          "inline-flex items-center justify-center gap-2 font-display font-bold tracking-tight transition-all cursor-pointer",
          "active:scale-[0.98]",
          "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:ring-[var(--brand-primary)]",
          "disabled:cursor-not-allowed disabled:bg-hero-grey-200 disabled:text-hero-grey-400 disabled:shadow-none disabled:translate-y-0",
          "disabled:hover:bg-hero-grey-200 disabled:hover:shadow-none disabled:hover:translate-y-0 disabled:active:scale-100",
          kh_button_size_classes(@size),
          kh_button_variant_classes(@variant),
          @class
        ]
      }
      {@rest}
    >
      <.icon :if={@icon} name={@icon} class="w-4 h-4" />
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp kh_button_size_classes(:sm), do: "px-3.5 py-2 text-sm rounded-lg"
  defp kh_button_size_classes(:md), do: "px-5 py-3 text-[15px] rounded-xl"
  defp kh_button_size_classes(:lg), do: "px-7 py-3.5 text-lg rounded-xl"

  defp kh_button_variant_classes(:primary),
    do:
      "bg-[var(--brand-primary)] hover:bg-[var(--brand-primary-hover)] text-black hover:shadow-lg hover:-translate-y-px"

  defp kh_button_variant_classes(:secondary),
    do:
      "bg-[var(--brand-accent)] hover:bg-[var(--brand-accent-hover)] text-black hover:shadow-md hover:-translate-y-0.5"

  defp kh_button_variant_classes(:ghost),
    do: "bg-transparent text-[var(--fg-primary)] border border-[var(--border-medium)] hover:bg-hero-grey-100"

  defp kh_button_variant_classes(:dark), do: "bg-black text-white hover:bg-[#1a1a1a] hover:shadow-md"

  defp kh_button_variant_classes(:yellow),
    do: "bg-hero-yellow-500 text-black hover:bg-hero-yellow-600 hover:shadow-md hover:-translate-y-0.5"

  @doc """
  Renders a Klass Hero card.

  Maps to bundle's `KhCard` (Primitives.jsx:111). Unlike the legacy `card/1`,
  this component takes a single inner block — header/body/footer dividers are
  the caller's responsibility, which is closer to how `<KhCard>` is used in
  the design bundle.

  ## Examples

      <.kh_card>Hello</.kh_card>
      <.kh_card variant={:dark} class="p-6">…</.kh_card>
  """
  attr :variant, :atom,
    default: :default,
    values: [:default, :elevated, :outlined, :glass, :muted, :dark, :soft]

  attr :class, :string, default: ""
  attr :rest, :global, include: ~w(phx-click phx-value-* navigate patch)
  slot :inner_block, required: true

  def kh_card(assigns) do
    ~H"""
    <div class={["rounded-2xl transition-all", kh_card_variant_classes(@variant), @class]} {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp kh_card_variant_classes(:default), do: "bg-white border border-[var(--border-light)] shadow-sm"

  defp kh_card_variant_classes(:elevated), do: "bg-white shadow-lg"

  defp kh_card_variant_classes(:outlined), do: "bg-white border-2 border-[var(--brand-primary)]"

  defp kh_card_variant_classes(:glass),
    do: "bg-white/80 backdrop-blur-sm border border-white/50 shadow-[0_8px_32px_rgba(31,38,135,0.25)]"

  defp kh_card_variant_classes(:muted), do: "bg-[var(--hero-cream-100)] border border-[var(--border-light)]"

  defp kh_card_variant_classes(:dark), do: "bg-black text-white"

  defp kh_card_variant_classes(:soft), do: "bg-[var(--hero-pink-50)] border border-[var(--border-light)]"

  @doc """
  Renders a Klass Hero pill / inline status badge.

  Maps to bundle's `KhPill` (Primitives.jsx:93). Independent of legacy
  `status_pill/1`, which uses a different `color` API.

  ## Examples

      <.kh_pill tone={:success}>Verified</.kh_pill>
      <.kh_pill tone={:dark}>This week</.kh_pill>
      <.kh_pill tone={:success} size={:xs}>Verified</.kh_pill>
  """
  attr :tone, :atom,
    default: :outline,
    values: [:primary, :accent, :outline, :success, :warning, :error, :info, :dark, :cream, :none],
    doc: "`:none` emits no colors — the caller supplies them through `class`"

  attr :size, :atom,
    default: :default,
    values: [:default, :xs],
    doc: "`:xs` is the dense variant for pills sharing a line with other text"

  attr :class, :string, default: ""
  attr :rest, :global
  slot :inner_block, required: true

  def kh_pill(assigns) do
    ~H"""
    <span
      class={[
        "inline-flex items-center rounded-full",
        kh_pill_size_classes(@size),
        kh_pill_tone_classes(@tone),
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp kh_pill_size_classes(:default), do: "gap-1.5 px-3 py-1 text-xs font-semibold"
  defp kh_pill_size_classes(:xs), do: "gap-1 px-1.5 py-0.5 text-xs font-medium flex-shrink-0"

  @doc """
  Renders a provider's vetting state inline beside their name.

  Lives here rather than with either card because both card families render it:
  `ProgramComponents.program_card/1` on `/programs` and the parent dashboard, and
  `MarketingComponents.mk_program_card/1` on the home page. The roomier
  `ProviderComponents.verification_status_badge/1` stays separate — it is a
  labelled pill for the provider's own dashboard header, too heavy to sit next to
  a name in a card.

  `:unverified` renders nothing: a provider who has not completed vetting gets no
  mark rather than a negative one.

  `variant={:compact}` shortens the in-progress label. The marketing card puts the
  mark on the same line as the provider name, where the full "Verification in
  progress" would push that line to wrap at mobile width (#1224).

  Colors come from `Theme.status_badge/1` rather than `kh_pill`'s `:success` /
  `:warning` tones, which pair a tint background with a mid-tone accent color and
  measure 2.4:1 and 2.1:1 — below WCAG AA's 4.5:1 for text this size. The
  `status_badge` pairs measure 6.5:1 and 6.4:1.

  ## Examples

      <.kh_trust_mark state={:verified} />
      <.kh_trust_mark state={:in_progress} variant={:compact} />
  """
  attr :state, :atom, required: true, values: [:verified, :in_progress, :unverified]

  attr :variant, :atom,
    default: :default,
    values: [:default, :compact],
    doc: "`:compact` shortens the in-progress label for dense, shared lines"

  def kh_trust_mark(%{state: :verified} = assigns) do
    ~H"""
    <.kh_pill
      tone={:none}
      size={:xs}
      class={Theme.status_badge(:available)}
      data-testid="provider-trust-mark"
      data-trust-state="verified"
      title={gettext("This provider completed Klass Hero's verification checks")}
    >
      <.icon name="hero-check-badge-mini" class="w-3.5 h-3.5" />
      <span>{gettext("Verified")}</span>
    </.kh_pill>
    """
  end

  def kh_trust_mark(%{state: :in_progress} = assigns) do
    ~H"""
    <.kh_pill
      tone={:none}
      size={:xs}
      class={Theme.status_badge(:limited)}
      data-testid="provider-trust-mark"
      data-trust-state="in_progress"
      title={gettext("This provider is working through Klass Hero's verification checks")}
    >
      <.icon name="hero-clock-mini" class="w-3.5 h-3.5" />
      <span>
        <%= if @variant == :compact do %>
          {gettext("Verifying")}
        <% else %>
          {gettext("Verification in progress")}
        <% end %>
      </span>
    </.kh_pill>
    """
  end

  def kh_trust_mark(assigns), do: ~H""

  defp kh_pill_tone_classes(:primary), do: "bg-[var(--brand-primary)] text-black"
  defp kh_pill_tone_classes(:accent), do: "bg-[var(--hero-yellow-500)] text-black"

  defp kh_pill_tone_classes(:outline), do: "bg-white text-[var(--fg-primary)] border border-[var(--border-medium)]"

  defp kh_pill_tone_classes(:success), do: "bg-[var(--success-bg)] text-[var(--success)]"
  defp kh_pill_tone_classes(:warning), do: "bg-[var(--warning-bg)] text-[var(--warning)]"
  defp kh_pill_tone_classes(:error), do: "bg-[var(--error-bg)] text-[var(--error)]"
  defp kh_pill_tone_classes(:info), do: "bg-[var(--info-bg)] text-[var(--info)]"
  defp kh_pill_tone_classes(:dark), do: "bg-black text-white"
  defp kh_pill_tone_classes(:cream), do: "bg-[var(--hero-cream-100)] text-[var(--fg-body)]"
  defp kh_pill_tone_classes(:none), do: ""

  @doc """
  Renders a heroicon. Convenience alias matching the `Kh*` naming so handoff
  components don't need a separate import path.
  """
  attr :name, :string, required: true
  attr :class, :string, default: "w-5 h-5"

  def kh_icon(assigns) do
    ~H"""
    <.icon name={@name} class={@class} />
    """
  end

  @doc """
  Renders a gradient icon chip.

  Maps to bundle's `KhIconChip` (Primitives.jsx:125). Independent of the
  legacy `gradient_icon/1` so that named gradients (`:primary`, `:comic`,
  `:cool`, `:art`, `:safety`, `:dark`, `:yellow`, `:pink`, `:mixed`) can be
  passed without callers having to know Tailwind class names.

  ## Examples

      <.kh_icon_chip icon="hero-academic-cap" gradient={:primary} />
      <.kh_icon_chip icon="hero-sparkles" gradient={:cool} size={:lg} />
  """
  attr :icon, :string, required: true

  attr :gradient, :atom,
    default: :primary,
    values: [:primary, :comic, :cool, :art, :safety, :dark, :yellow, :pink, :mixed]

  attr :size, :atom, default: :md, values: [:sm, :md, :lg]
  attr :class, :string, default: ""

  def kh_icon_chip(assigns) do
    ~H"""
    <div
      class={[
        "flex items-center justify-center",
        kh_icon_chip_size_classes(@size),
        kh_icon_chip_text_color(@gradient),
        @class
      ]}
      style={"background: #{kh_icon_chip_gradient(@gradient)}"}
    >
      <.icon name={@icon} class={kh_icon_chip_icon_size(@size)} />
    </div>
    """
  end

  defp kh_icon_chip_size_classes(:sm), do: "w-9 h-9 rounded-lg"
  defp kh_icon_chip_size_classes(:md), do: "w-12 h-12 rounded-xl"
  defp kh_icon_chip_size_classes(:lg), do: "w-16 h-16 rounded-2xl"

  defp kh_icon_chip_icon_size(:sm), do: "w-5 h-5"
  defp kh_icon_chip_icon_size(:md), do: "w-6 h-6"
  defp kh_icon_chip_icon_size(:lg), do: "w-8 h-8"

  defp kh_icon_chip_gradient(:primary), do: "var(--grad-primary)"
  defp kh_icon_chip_gradient(:comic), do: "var(--grad-comic)"
  defp kh_icon_chip_gradient(:cool), do: "var(--grad-cool)"
  defp kh_icon_chip_gradient(:art), do: "var(--grad-art)"
  defp kh_icon_chip_gradient(:safety), do: "var(--grad-safety)"
  defp kh_icon_chip_gradient(:dark), do: "linear-gradient(135deg,#1A1A1A 0%,#000 100%)"
  defp kh_icon_chip_gradient(:yellow), do: "var(--hero-yellow-500)"
  defp kh_icon_chip_gradient(:pink), do: "var(--hero-pink-50)"
  defp kh_icon_chip_gradient(:mixed), do: "var(--grad-hero)"

  defp kh_icon_chip_text_color(g) when g in [:cool, :safety, :dark], do: "text-white"
  defp kh_icon_chip_text_color(_), do: "text-black"

  @doc """
  Renders a horizontal list row primitive.

  Maps to bundle's `KhListRow` (Primitives.jsx:186). Used for sessions roster,
  request cards, program rows, message-thread items — anywhere a media column,
  title, optional meta/stats, trailing actions, and an optional full-width
  footer line up in a grid.

  Slot contract:
  - `media` — leading visual (avatar, cover, icon chip)
  - `title` *(required)* — primary label
  - `pill` — optional `<.kh_pill>` alongside the title
  - `actions` — trailing button(s)
  - `footer` — full-width row beneath the main row

  Attrs:
  - `meta` — string or list of strings rendered with `·` separators
  - `stats` — list of `%{value: term, label: term}` maps rendered inline

  ## Examples

      <.kh_list_row hover meta={["Mon 14:00", "Studio A"]}>
        <:title>Football Stars</:title>
      </.kh_list_row>
  """
  attr :density, :atom, default: :comfortable, values: [:compact, :comfortable]
  attr :hover, :boolean, default: false
  attr :meta, :any, default: nil, doc: "string or list of strings"
  attr :stats, :list, default: nil, doc: "list of %{value: _, label: _}"
  attr :class, :string, default: ""
  attr :rest, :global, include: ~w(phx-click phx-value-*)

  slot :media
  slot :title, required: true
  slot :pill
  slot :actions
  slot :footer

  def kh_list_row(assigns) do
    assigns = assign(assigns, :meta_items, kh_list_row_meta_items(assigns.meta))

    ~H"""
    <div
      class={[
        "rounded-xl",
        if(@density == :compact, do: "p-2.5", else: "p-3"),
        @hover && "hover:bg-[var(--hero-cream-100)] transition-colors",
        @rest[:"phx-click"] && "cursor-pointer",
        @class
      ]}
      {@rest}
    >
      <div class={["flex items-start", if(@density == :compact, do: "gap-3", else: "gap-4")]}>
        <div :if={@media != []} class="shrink-0">{render_slot(@media)}</div>
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2 flex-wrap">
            <span class="font-bold text-sm leading-tight truncate">
              {render_slot(@title)}
            </span>
            <span :if={@pill != []}>{render_slot(@pill)}</span>
          </div>
          <div
            :if={@meta_items != []}
            class="text-xs text-[var(--fg-muted)] mt-1 flex gap-x-2.5 gap-y-0.5 flex-wrap"
          >
            <%= for {item, idx} <- Enum.with_index(@meta_items) do %>
              <span
                :if={idx > 0}
                aria-hidden="true"
                class="text-[var(--border-medium)]"
              >
                ·
              </span>
              <span>{item}</span>
            <% end %>
          </div>
          <div
            :if={is_list(@stats) and @stats != []}
            class="text-xs mt-1.5 flex items-baseline gap-x-3 gap-y-0.5 flex-wrap"
          >
            <span :for={s <- @stats}>
              <%!-- typography-lint-ignore: KhListRow stats render numeric callouts in display font --%>
              <span class="font-display font-extrabold">{s.value}</span>
              <span :if={s[:label]} class="text-[var(--fg-muted)] font-normal">
                {" "}{s.label}
              </span>
            </span>
          </div>
        </div>
        <div :if={@actions != []} class="shrink-0 flex items-center gap-2">
          {render_slot(@actions)}
        </div>
      </div>
      <div :if={@footer != []} class="mt-3">{render_slot(@footer)}</div>
    </div>
    """
  end

  defp kh_list_row_meta_items(nil), do: []
  defp kh_list_row_meta_items([]), do: []
  defp kh_list_row_meta_items(list) when is_list(list), do: Enum.reject(list, &is_nil/1)
  defp kh_list_row_meta_items(other), do: [other]

  # Brand marks, 24x24, single-path, `fill="currentColor"` so they take the link's
  # colour. DESIGN.md's "no second icon set" rule is about icon *libraries* —
  # Heroicons ships no brand glyphs, and these five are not a library. Facebook and
  # Instagram are the paths the footer already carried before this was extracted.
  @social_paths %{
    facebook:
      "M24 12.073c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.99 4.388 10.954 10.125 11.854v-8.385H7.078v-3.47h3.047V9.43c0-3.007 1.792-4.669 4.533-4.669 1.312 0 2.686.235 2.686.235v2.953H15.83c-1.491 0-1.956.925-1.956 1.874v2.25h3.328l-.532 3.47h-2.796v8.385C19.612 23.027 24 18.062 24 12.073z",
    instagram:
      "M12 2.163c3.204 0 3.584.012 4.85.07 3.252.148 4.771 1.691 4.919 4.919.058 1.265.069 1.645.069 4.849 0 3.205-.012 3.584-.069 4.849-.149 3.225-1.664 4.771-4.919 4.919-1.266.058-1.644.07-4.85.07-3.204 0-3.584-.012-4.849-.07-3.26-.149-4.771-1.699-4.919-4.92-.058-1.265-.07-1.644-.07-4.849 0-3.204.013-3.583.07-4.849.149-3.227 1.664-4.771 4.919-4.919 1.266-.057 1.645-.069 4.849-.069zm0-2.163c-3.259 0-3.667.014-4.947.072-4.358.2-6.78 2.618-6.98 6.98-.059 1.281-.073 1.689-.073 4.948 0 3.259.014 3.668.072 4.948.2 4.358 2.618 6.78 6.98 6.98 1.281.058 1.689.072 4.948.072 3.259 0 3.668-.014 4.948-.072 4.354-.2 6.782-2.618 6.979-6.98.059-1.28.073-1.689.073-4.948 0-3.259-.014-3.667-.072-4.947-.196-4.354-2.617-6.78-6.979-6.98-1.281-.059-1.69-.073-4.949-.073zm0 5.838c-3.403 0-6.162 2.759-6.162 6.162s2.759 6.163 6.162 6.163 6.162-2.759 6.162-6.163c0-3.403-2.759-6.162-6.162-6.162zm0 10.162c-2.209 0-4-1.79-4-4 0-2.209 1.791-4 4-4s4 1.791 4 4c0 2.21-1.791 4-4 4zm6.406-11.845c-.796 0-1.441.645-1.441 1.44s.645 1.44 1.441 1.44c.795 0 1.439-.645 1.439-1.44s-.644-1.44-1.439-1.44z",
    tiktok:
      "M12.525.02c1.31-.02 2.61-.01 3.91-.02.08 1.53.63 3.09 1.75 4.17 1.12 1.11 2.7 1.62 4.24 1.79v4.03c-1.44-.05-2.89-.35-4.2-.97-.57-.26-1.1-.59-1.62-.93-.01 2.92.01 5.84-.02 8.75-.08 1.4-.54 2.79-1.35 3.94-1.31 1.92-3.58 3.17-5.91 3.21-1.43.08-2.86-.31-4.08-1.03-2.02-1.19-3.44-3.37-3.65-5.71-.02-.5-.03-1-.01-1.49.18-1.9 1.12-3.72 2.58-4.96 1.66-1.44 3.98-2.13 6.15-1.72.02 1.48-.04 2.96-.04 4.44-.99-.32-2.15-.23-3.02.37-.63.41-1.11 1.04-1.36 1.75-.21.51-.15 1.07-.14 1.61.24 1.64 1.82 3.02 3.5 2.87 1.12-.01 2.19-.66 2.77-1.61.19-.33.4-.67.41-1.06.1-1.79.06-3.57.07-5.36.01-4.03-.01-8.05.02-12.07z",
    youtube:
      "M23.498 6.186a3.016 3.016 0 0 0-2.122-2.136C19.505 3.545 12 3.545 12 3.545s-7.505 0-9.377.505A3.017 3.017 0 0 0 .502 6.186C0 8.07 0 12 0 12s0 3.93.502 5.814a3.016 3.016 0 0 0 2.122 2.136c1.871.505 9.376.505 9.376.505s7.505 0 9.377-.505a3.015 3.015 0 0 0 2.122-2.136C24 15.93 24 12 24 12s0-3.93-.502-5.814zM9.545 15.568V8.432L15.818 12l-6.273 3.568z",
    linkedin:
      "M20.447 20.452h-3.554v-5.569c0-1.328-.027-3.037-1.852-3.037-1.853 0-2.136 1.445-2.136 2.939v5.667H9.351V9h3.414v1.561h.046c.477-.9 1.637-1.85 3.37-1.85 3.601 0 4.267 2.37 4.267 5.455v6.286zM5.337 7.433a2.062 2.062 0 0 1-2.063-2.065 2.064 2.064 0 1 1 2.063 2.065zm1.782 13.019H3.555V9h3.564v11.452zM22.225 0H1.771C.792 0 0 .774 0 1.729v20.542C0 23.227.792 24 1.771 24h20.451C23.2 24 24 23.227 24 22.271V1.729C24 .774 23.2 0 22.225 0z"
  }

  # Every network `KlassHero.SocialLinks` declares must have a glyph here. Without
  # this, adding a network would render an empty `<svg>` — no error, no test
  # failure, just a missing icon nobody notices.
  for network <- KlassHero.SocialLinks.networks() do
    if !Map.has_key?(@social_paths, network) do
      raise "kh_social_icon/1 has no SVG path for #{inspect(network)} — add one to @social_paths"
    end
  end

  @doc """
  Renders a social network's brand mark as an inline SVG.

  Keyed on the network **atom**, never on a display label — a glyph lookup keyed on
  translatable or editable text breaks silently the first time that text changes.

  The glyph alone is not an accessible name, so every caller must supply one. This
  component renders only the mark; the `<a>`, its `aria-label` and its
  `rel="noopener noreferrer"` belong to the caller, which is the only place that
  knows whether the link is Klass Hero's own (`KlassHero.SocialLinks`) or a
  provider's (`ProviderPresenter.social_links/1`).

  ## Examples

      <.kh_social_icon network={:instagram} />
      <.kh_social_icon network={:tiktok} class="w-6 h-6" />
  """
  attr :network, :atom, required: true, values: KlassHero.SocialLinks.networks()
  attr :class, :string, default: "w-5 h-5"

  def kh_social_icon(assigns) do
    assigns = assign(assigns, :path, Map.fetch!(@social_paths, assigns.network))

    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="currentColor"
      aria-hidden="true"
      focusable="false"
      class={@class}
    >
      <path d={@path} />
    </svg>
    """
  end
end
