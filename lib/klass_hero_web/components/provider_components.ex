defmodule KlassHeroWeb.ProviderComponents do
  @moduledoc """
  UI components specific to the provider dashboard.
  """
  use Phoenix.Component
  use Gettext, backend: KlassHeroWeb.Gettext

  use Phoenix.VerifiedRoutes,
    endpoint: KlassHeroWeb.Endpoint,
    router: KlassHeroWeb.Router,
    statics: KlassHeroWeb.static_paths()

  import KlassHeroWeb.CoreComponents, only: [input: 1]
  import KlassHeroWeb.ParticipationComponents, only: [participation_status: 1]
  import KlassHeroWeb.UIComponents

  alias KlassHeroWeb.Presenters.ProviderPresenter
  alias KlassHeroWeb.Theme

  @doc """
  Renders a colored status badge for a verification document status.

  ## Examples

      <.doc_status_badge status={:pending} />
      <.doc_status_badge status={:approved} />
  """
  attr :status, :atom, required: true

  def doc_status_badge(assigns) do
    {bg_class, text_class, label} = doc_status_style(assigns.status)
    assigns = assign(assigns, bg_class: bg_class, text_class: text_class, label: label)

    ~H"""
    <span class={[
      "px-2.5 py-1 text-xs font-medium",
      Theme.rounded(:full),
      @bg_class,
      @text_class
    ]}>
      {@label}
    </span>
    """
  end

  defp doc_status_style(:pending), do: {"bg-yellow-100", "text-yellow-800", gettext("Pending")}
  defp doc_status_style(:approved), do: {"bg-green-100", "text-green-800", gettext("Approved")}
  defp doc_status_style(:rejected), do: {"bg-red-100", "text-red-800", gettext("Rejected")}
  defp doc_status_style(_), do: {"bg-hero-grey-100", "text-hero-grey-600", gettext("Unknown")}

  @doc """
  Renders the provider dashboard tab navigation.

  `current_tab` is the active tab as the *component* understands it
  (`:overview`, `:team`, `:programs`, `:sessions`). Callers translate their
  own `@live_action` into this vocabulary, so the nav stays decoupled from
  any single LiveView's routing scheme.

  ## Examples

      <.provider_nav_tabs current_tab={:overview} />
      <.provider_nav_tabs current_tab={:sessions} />
  """
  attr :current_tab, :atom, required: true

  def provider_nav_tabs(assigns) do
    ~H"""
    <nav class="border-b border-hero-grey-200 mb-6">
      <div class="flex gap-1 overflow-x-auto pb-px -mb-px">
        <.nav_tab
          patch={~p"/provider/dashboard"}
          active={@current_tab == :overview}
          icon="hero-squares-2x2-mini"
        >
          {gettext("Overview")}
        </.nav_tab>
        <.nav_tab
          patch={~p"/provider/dashboard/team"}
          active={@current_tab == :team}
          icon="hero-user-group-mini"
        >
          {gettext("Team & Profiles")}
        </.nav_tab>
        <.nav_tab
          patch={~p"/provider/dashboard/programs"}
          active={@current_tab == :programs}
          icon="hero-queue-list-mini"
        >
          {gettext("My Programs")}
        </.nav_tab>
        <.nav_tab
          navigate={~p"/provider/sessions"}
          active={@current_tab == :sessions}
          icon="hero-calendar-days-mini"
        >
          {gettext("Sessions")}
        </.nav_tab>
      </div>
    </nav>
    """
  end

  attr :patch, :string, default: nil
  attr :navigate, :string, default: nil
  attr :active, :boolean, required: true
  attr :icon, :string, required: true
  slot :inner_block, required: true

  defp nav_tab(assigns) do
    ~H"""
    <.link
      patch={@patch}
      navigate={@navigate}
      class={[
        "flex items-center gap-2 px-4 py-3 text-sm font-medium whitespace-nowrap border-b-2 transition-colors",
        if(@active,
          do: "border-hero-cyan text-hero-cyan",
          else:
            "border-transparent text-hero-grey-500 hover:text-hero-grey-700 hover:border-hero-grey-300"
        )
      ]}
    >
      <.icon name={@icon} class="w-5 h-5" />
      {render_slot(@inner_block)}
    </.link>
    """
  end

  @doc """
  Renders a stat card for the provider dashboard.

  ## Examples

      <.provider_stat_card
        label="Total Revenue"
        value="12,500"
        icon="hero-currency-euro-mini"
        icon_bg="bg-hero-cyan-100"
        icon_color="text-hero-cyan"
      />
  """
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :icon, :string, required: true
  attr :icon_bg, :string, default: "bg-hero-cyan-100"
  attr :icon_color, :string, default: "text-hero-cyan"

  def provider_stat_card(assigns) do
    ~H"""
    <div class={[
      "bg-white p-4 shadow-sm border border-hero-grey-200",
      Theme.rounded(:xl)
    ]}>
      <div class="flex items-center gap-3">
        <div class={["w-10 h-10 flex items-center justify-center", Theme.rounded(:lg), @icon_bg]}>
          <.icon name={@icon} class={"w-5 h-5 #{@icon_color}"} />
        </div>
        <div>
          <p class="text-sm text-hero-grey-500">{@label}</p>
          <p class="text-2xl font-bold text-hero-charcoal">{@value}</p>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders the business profile card with verification badges.

  ## Examples

      <.business_profile_card business={@business} />
  """
  attr :business, :map, required: true

  def business_profile_card(assigns) do
    ~H"""
    <div class={["bg-white p-6 shadow-sm border border-hero-grey-200", Theme.rounded(:xl)]}>
      <div class="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-4 mb-4">
        <div>
          <h2 class="text-xl font-semibold text-hero-charcoal mb-1">
            {gettext("Business Profile")}
          </h2>
          <p class="text-sm text-hero-grey-500">
            {gettext(
              "This is your main business identity. Verification is required to list programs."
            )}
          </p>
        </div>
        <.link
          navigate={~p"/provider/dashboard/edit"}
          class={[
            "flex items-center gap-2 px-4 py-2 border border-hero-grey-300 bg-white",
            "hover:bg-hero-grey-50 text-hero-charcoal text-sm font-medium",
            Theme.rounded(:lg),
            Theme.transition(:normal)
          ]}
        >
          <.icon name="hero-pencil-square-mini" class="w-4 h-4" />
          {gettext("Edit Profile")}
        </.link>
      </div>

      <div class="flex items-center gap-4">
        <%!-- Logo: real image or initials placeholder --%>
        <img
          :if={@business.logo_url}
          src={@business.logo_url}
          alt={@business.name}
          id="business-logo"
          class={["w-20 h-20 object-cover", Theme.rounded(:full)]}
        />
        <div
          :if={!@business.logo_url}
          id="business-logo-placeholder"
          class={[
            "w-20 h-20 flex items-center justify-center text-white text-2xl font-bold",
            Theme.rounded(:full),
            Theme.gradient(:primary)
          ]}
        >
          {@business.initials}
        </div>
        <div>
          <h3 class="text-xl font-semibold text-hero-charcoal">{@business.name}</h3>
          <p class="text-hero-grey-500 mb-2">{@business.tagline}</p>
          <div class="flex flex-wrap gap-2">
            <.verification_status_badge status={@business.verification_status} />
            <.verification_badge
              :for={badge <- @business.verification_badges}
              icon={badge_icon(badge.key)}
              label={badge.label}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :status, :atom, required: true

  defp verification_status_badge(%{status: :verified} = assigns) do
    ~H"""
    <div
      id="verification-status"
      class={[
        "flex items-center gap-1.5 px-3 py-1.5 bg-green-100 text-green-700 text-xs font-medium",
        Theme.rounded(:full)
      ]}
    >
      <.icon name="hero-check-badge-mini" class="w-4 h-4" />
      <span class="uppercase tracking-wide">{gettext("Verified")}</span>
    </div>
    """
  end

  defp verification_status_badge(%{status: :pending} = assigns) do
    ~H"""
    <div
      id="verification-status"
      class={[
        "flex items-center gap-1.5 px-3 py-1.5 bg-yellow-100 text-yellow-700 text-xs font-medium",
        Theme.rounded(:full)
      ]}
    >
      <.icon name="hero-clock-mini" class="w-4 h-4" />
      <span class="uppercase tracking-wide">{gettext("Pending Review")}</span>
    </div>
    """
  end

  defp verification_status_badge(%{status: :rejected} = assigns) do
    ~H"""
    <div
      id="verification-status"
      class={[
        "flex items-center gap-1.5 px-3 py-1.5 bg-red-100 text-red-700 text-xs font-medium",
        Theme.rounded(:full)
      ]}
    >
      <.icon name="hero-x-circle-mini" class="w-4 h-4" />
      <span class="uppercase tracking-wide">{gettext("Action Required")}</span>
    </div>
    """
  end

  defp verification_status_badge(assigns) do
    ~H"""
    <div
      id="verification-status"
      class={[
        "flex items-center gap-1.5 px-3 py-1.5 bg-hero-grey-100 text-hero-grey-500 text-xs font-medium",
        Theme.rounded(:full)
      ]}
    >
      <.icon name="hero-document-plus-mini" class="w-4 h-4" />
      <span class="uppercase tracking-wide">{gettext("Not Verified")}</span>
    </div>
    """
  end

  defp badge_icon(:business_registration), do: "hero-check-badge-mini"
  defp badge_icon(:insurance), do: "hero-shield-check-mini"
  defp badge_icon(_), do: "hero-check-mini"

  attr :status, :atom, required: true
  attr :label, :string, required: true

  defp invitation_status_badge(assigns) do
    {bg_class, text_class} = invitation_status_colors(assigns.status)
    assigns = assign(assigns, bg_class: bg_class, text_class: text_class)

    ~H"""
    <span class={[
      "shrink-0 px-2 py-0.5 text-xs font-medium",
      Theme.rounded(:full),
      @bg_class,
      @text_class
    ]}>
      {@label}
    </span>
    """
  end

  defp invitation_status_colors(:pending), do: {"bg-yellow-100", "text-yellow-700"}
  defp invitation_status_colors(:sent), do: {"bg-blue-100", "text-blue-700"}
  defp invitation_status_colors(:accepted), do: {"bg-green-100", "text-green-700"}
  defp invitation_status_colors(:failed), do: {"bg-red-100", "text-red-700"}
  defp invitation_status_colors(:expired), do: {"bg-hero-grey-100", "text-hero-grey-600"}
  defp invitation_status_colors(_), do: {"bg-hero-grey-100", "text-hero-grey-500"}

  attr :icon, :string, required: true
  attr :label, :string, required: true

  defp verification_badge(assigns) do
    ~H"""
    <div class={[
      "flex items-center gap-1.5 px-3 py-1.5 bg-hero-grey-100 text-hero-grey-700 text-xs font-medium",
      Theme.rounded(:full)
    ]}>
      <.icon name={@icon} class="w-4 h-4 text-green-600" />
      <span class="uppercase tracking-wide">{@label}</span>
    </div>
    """
  end

  @doc """
  Renders the dashboard header with business name and badges.

  ## Examples

      <.provider_dashboard_header business={@business} />
  """
  attr :business, :map, required: true

  def provider_dashboard_header(assigns) do
    ~H"""
    <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-4 mb-6">
      <div>
        <h1 class="text-2xl font-bold text-hero-charcoal mb-2">
          {@business.name} {gettext("Dashboard")}
        </h1>
        <div class="flex flex-wrap items-center gap-2">
          <span
            :if={@business.verified}
            class={[
              "flex items-center gap-1 px-3 py-1 text-xs font-medium border border-green-500 text-green-600",
              Theme.rounded(:full)
            ]}
          >
            <.icon name="hero-check-badge-mini" class="w-4 h-4" />
            {gettext("Verified Business")}
          </span>
        </div>
      </div>

      <div class="flex items-center gap-4">
        <div class="relative group">
          <.kh_button
            id="new-program-btn"
            variant={:yellow}
            size={:sm}
            icon="hero-plus-mini"
            phx-click="add_program"
            disabled={@business.verification_status != :verified}
          >
            {gettext("New Program")}
          </.kh_button>
          <%!-- Tooltip: shown only when button is disabled --%>
          <div
            :if={@business.verification_status != :verified}
            id="new-program-tooltip"
            class={[
              "absolute right-0 top-full mt-2 w-64 p-3 bg-hero-charcoal text-white text-xs",
              "opacity-0 group-hover:opacity-100 pointer-events-none z-10",
              Theme.rounded(:lg),
              Theme.transition(:normal)
            ]}
          >
            {gettext("Complete business verification to create programs.")}
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a team member card.

  `rate_label` is an explicit attr so the parent-facing caller (program detail page)
  passes nothing and the admin caller passes `@member.rate_label`. Never sniff the
  presence of a key on `@member` to decide whether to show the rate — that would
  re-enable the leak path the presenter split was designed to close.

  ## Examples

      <.team_member_card member={member} />
      <.team_member_card member={member} rate_label={member.rate_label} />
  """
  attr :member, :map, required: true
  attr :rate_label, :string, default: nil

  def team_member_card(assigns) do
    ~H"""
    <div class={["bg-white shadow-sm border border-hero-grey-200 overflow-hidden", Theme.rounded(:xl)]}>
      <div class="relative h-24 bg-gradient-to-r from-hero-grey-200 to-hero-grey-300">
        <div
          :if={@member.role}
          class={[
            "absolute top-2 right-2 px-2 py-1 bg-white/90 text-xs font-medium text-hero-charcoal",
            Theme.rounded(:md)
          ]}
        >
          {@member.role}
        </div>
        <%!-- Headshot image or initials avatar --%>
        <img
          :if={@member.headshot_url}
          src={@member.headshot_url}
          alt={@member.full_name}
          class={[
            "absolute -bottom-8 left-4 w-16 h-16 object-cover border-4 border-white",
            Theme.rounded(:full)
          ]}
        />
        <div
          :if={!@member.headshot_url}
          class={[
            "absolute -bottom-8 left-4 w-16 h-16 flex items-center justify-center",
            "text-white text-xl font-bold border-4 border-white",
            Theme.rounded(:full),
            Theme.gradient(:primary)
          ]}
        >
          {@member.initials}
        </div>
      </div>

      <div class="pt-10 px-4 pb-4">
        <div class="flex items-start justify-between gap-2 mb-1">
          <h3 class="font-semibold text-hero-charcoal">{@member.full_name}</h3>
          <.invitation_status_badge
            :if={@member.invitation_status != nil}
            status={@member.invitation_status}
            label={@member.invitation_status_label}
          />
        </div>
        <p :if={@member.email} class="text-sm text-hero-grey-500 mb-2">{@member.email}</p>
        <p :if={@member.bio} class="text-sm text-hero-grey-600 mb-3 line-clamp-2">{@member.bio}</p>

        <%!-- Category tags as colored pills --%>
        <div :if={@member.tags != []} class="flex flex-wrap gap-1.5 mb-3">
          <span
            :for={tag <- @member.tags}
            class={[
              "px-2 py-1 text-xs font-medium bg-hero-cyan-100 text-hero-cyan",
              Theme.rounded(:full)
            ]}
          >
            {tag}
          </span>
        </div>

        <%!-- Qualifications as badge pills --%>
        <div :if={@member.qualifications != []} class="flex flex-wrap gap-1.5 mb-3">
          <span
            :for={qual <- @member.qualifications}
            class={[
              "px-2 py-1 text-xs font-medium border border-hero-grey-300 text-hero-grey-600",
              Theme.rounded(:md)
            ]}
          >
            {qual}
          </span>
        </div>

        <%!-- Pay rate (admin-only — caller passes the label explicitly) --%>
        <p :if={@rate_label} class="text-sm text-hero-charcoal mb-3">
          <span class="font-semibold">{gettext("Pay rate")}:</span> {@rate_label}
        </p>

        <div class="flex items-center gap-2">
          <button
            type="button"
            phx-click="edit_member"
            phx-value-id={@member.id}
            class={[
              "flex-1 px-4 py-2 border border-hero-grey-300 bg-white",
              "hover:bg-hero-grey-50 text-hero-charcoal text-sm font-medium",
              Theme.rounded(:lg),
              Theme.transition(:normal)
            ]}
          >
            {gettext("Edit")}
          </button>
          <button
            :if={@member.can_resend?}
            type="button"
            id={"resend-invitation-#{@member.id}"}
            phx-click="resend_invitation"
            phx-value-id={@member.id}
            class={[
              "px-3 py-2 bg-hero-yellow hover:bg-hero-yellow-dark text-hero-charcoal text-xs font-medium",
              Theme.rounded(:lg),
              Theme.transition(:normal)
            ]}
          >
            {gettext("Resend")}
          </button>
          <button
            type="button"
            phx-click="delete_member"
            phx-value-id={@member.id}
            data-confirm={gettext("Are you sure you want to remove this team member?")}
            class={[
              "p-2 text-red-500 hover:bg-red-50",
              Theme.rounded(:lg),
              Theme.transition(:normal)
            ]}
          >
            <.icon name="hero-x-mark-mini" class="w-5 h-5" />
          </button>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders the staff member create/edit form.

  ## Examples

      <.staff_member_form form={@staff_form} editing={false} uploads={@uploads} />
  """
  attr :form, :any, required: true
  attr :editing, :boolean, default: false
  attr :uploads, :map, required: true
  attr :categories, :list, required: true, doc: "List of valid program categories"

  attr :email_readonly, :boolean,
    default: false,
    doc: "Self-staffing locks the email to the account address (#969)"

  def staff_member_form(assigns) do
    ~H"""
    <div
      id="staff-member-form"
      class={["bg-white p-6 shadow-sm border border-hero-grey-200", Theme.rounded(:xl)]}
    >
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-lg font-semibold text-hero-charcoal">
          <%= if @editing do %>
            {gettext("Edit Team Member")}
          <% else %>
            {gettext("Add Team Member")}
          <% end %>
        </h3>
        <button
          type="button"
          phx-click="close_staff_form"
          class={[
            "p-2 text-hero-grey-400 hover:text-hero-charcoal hover:bg-hero-grey-100",
            Theme.rounded(:lg)
          ]}
        >
          <.icon name="hero-x-mark-mini" class="w-5 h-5" />
        </button>
      </div>

      <.form
        for={@form}
        id="staff-form"
        phx-change="validate_staff"
        phx-submit="save_staff"
        class="space-y-4"
      >
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <.input
            field={@form[:first_name]}
            type="text"
            label={gettext("First Name")}
            placeholder={gettext("e.g. Mike")}
          />
          <.input
            field={@form[:last_name]}
            type="text"
            label={gettext("Last Name")}
            placeholder={gettext("e.g. Johnson")}
          />
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <.input
            field={@form[:role]}
            type="text"
            label={gettext("Role")}
            placeholder={gettext("e.g. Head Coach")}
          />
          <.input
            field={@form[:email]}
            type="email"
            label={gettext("Email")}
            placeholder={gettext("e.g. mike@example.com")}
            readonly={@email_readonly}
          />
        </div>

        <.input
          field={@form[:bio]}
          type="textarea"
          label={gettext("Bio")}
          placeholder={gettext("Brief description of experience and specialties...")}
        />

        <%!-- Tags as checkboxes --%>
        <div>
          <label class="block text-sm font-semibold text-hero-charcoal mb-2">
            {gettext("Specialties")}
          </label>
          <div class="flex flex-wrap gap-3">
            <label :for={cat <- @categories} class="flex items-center gap-2 text-sm">
              <input
                type="checkbox"
                name="staff_member_schema[tags][]"
                value={cat}
                checked={cat in ((@form[:tags] && @form[:tags].value) || [])}
                class="rounded border-hero-grey-300 text-hero-cyan focus:ring-hero-cyan"
              />
              {cat}
            </label>
          </div>
          <%!-- Hidden input to ensure empty tags array is sent when nothing is checked --%>
          <input type="hidden" name="staff_member_schema[tags][]" value="" />
        </div>

        <%!-- Qualifications as comma-separated text --%>
        <.input
          field={@form[:qualifications]}
          type="text"
          label={gettext("Qualifications")}
          placeholder={gettext("First Aid, UEFA B License, Child Care Cert")}
          value={qualifications_to_string(@form[:qualifications] && @form[:qualifications].value)}
        />
        <p class="text-xs text-hero-grey-400 -mt-2">
          {gettext("Separate multiple qualifications with commas")}
        </p>

        <%!-- Pay Rate (visible only to the business account; not rendered in parent-facing views) --%>
        <div>
          <label class="block text-sm font-semibold text-hero-charcoal mb-2">
            {gettext("Pay Rate")}
          </label>
          <div class="flex flex-wrap items-center gap-4">
            <label class="flex items-center gap-2 text-sm">
              <input
                type="radio"
                name="staff_member_schema[rate_type]"
                value=""
                checked={empty_rate_type?(@form[:rate_type])}
                class="border-hero-grey-300 text-hero-cyan focus:ring-hero-cyan"
              />
              {gettext("None")}
            </label>
            <label class="flex items-center gap-2 text-sm">
              <input
                type="radio"
                name="staff_member_schema[rate_type]"
                value="hourly"
                checked={rate_type_is?(@form[:rate_type], "hourly")}
                class="border-hero-grey-300 text-hero-cyan focus:ring-hero-cyan"
              />
              {gettext("Hourly")}
            </label>
            <label class="flex items-center gap-2 text-sm">
              <input
                type="radio"
                name="staff_member_schema[rate_type]"
                value="per_session"
                checked={rate_type_is?(@form[:rate_type], "per_session")}
                class="border-hero-grey-300 text-hero-cyan focus:ring-hero-cyan"
              />
              {gettext("Per Session")}
            </label>
          </div>
          <div class="mt-2 flex items-center gap-2">
            <span class="text-hero-charcoal font-medium" aria-hidden="true">€</span>
            <.input
              field={@form[:rate_amount]}
              type="number"
              step="0.01"
              min="0"
              placeholder="0.00"
              label=""
            />
            <%!-- Single-currency MVP for Berlin; extend via Money.valid_currencies/0 when we expand regions. --%>
            <input type="hidden" name="staff_member_schema[rate_currency]" value="EUR" />
          </div>
        </div>

        <%!-- Headshot upload --%>
        <div>
          <label class="block text-sm font-semibold text-hero-charcoal mb-2">
            {gettext("Headshot Photo")}
          </label>
          <div
            id="headshot-upload"
            class={[
              "border-2 border-dashed border-hero-grey-300 p-4 text-center",
              Theme.rounded(:lg)
            ]}
            phx-drop-target={@uploads.headshot.ref}
          >
            <div :for={entry <- @uploads.headshot.entries} class="mb-3">
              <.live_img_preview
                entry={entry}
                class="w-16 h-16 mx-auto rounded-full object-cover"
              />
              <button
                type="button"
                phx-click="cancel_upload"
                phx-value-ref={entry.ref}
                phx-value-upload="headshot"
                class="text-xs text-red-500 hover:text-red-700 mt-1"
              >
                {gettext("Remove")}
              </button>
            </div>

            <.live_file_input upload={@uploads.headshot} class="hidden" />
            <label
              for={@uploads.headshot.ref}
              class={[
                "inline-flex items-center gap-2 px-4 py-2 border border-hero-grey-300",
                "bg-white hover:bg-hero-grey-50 text-hero-charcoal text-sm font-medium cursor-pointer",
                Theme.rounded(:lg)
              ]}
            >
              <.icon name="hero-photo-mini" class="w-4 h-4" />
              {gettext("Choose Photo")}
            </label>
            <p class="text-xs text-hero-grey-400 mt-2">
              {gettext("JPG, PNG or WebP. Max 1MB.")}
            </p>
          </div>
        </div>

        <div class="flex items-center gap-3 pt-2">
          <button
            type="submit"
            id="save-staff-btn"
            class={[
              "flex items-center gap-2 px-6 py-2.5 bg-hero-yellow hover:bg-hero-yellow-dark",
              "text-hero-charcoal font-semibold active:scale-[0.98]",
              Theme.rounded(:lg),
              Theme.transition(:normal)
            ]}
          >
            <.icon name="hero-check-mini" class="w-5 h-5" />
            <%= if @editing do %>
              {gettext("Save Changes")}
            <% else %>
              {gettext("Add Member")}
            <% end %>
          </button>
          <button
            type="button"
            phx-click="close_staff_form"
            class={[
              "px-4 py-2.5 border border-hero-grey-300 bg-white",
              "hover:bg-hero-grey-50 text-hero-charcoal text-sm font-medium",
              Theme.rounded(:lg),
              Theme.transition(:normal)
            ]}
          >
            {gettext("Cancel")}
          </button>
        </div>
      </.form>
    </div>
    """
  end

  defp qualifications_to_string(nil), do: ""
  defp qualifications_to_string(quals) when is_list(quals), do: Enum.join(quals, ", ")
  defp qualifications_to_string(quals) when is_binary(quals), do: quals

  defp empty_rate_type?(nil), do: true
  defp empty_rate_type?(field), do: field.value in [nil, ""]

  defp rate_type_is?(nil, _value), do: false
  defp rate_type_is?(field, value), do: to_string(field.value) == value

  @doc """
  Renders the program create/edit form.

  ## Examples

      <.program_form form={@program_form} uploads={@uploads} instructor_options={@instructor_options} />
  """
  attr :form, :any, required: true
  attr :enrollment_form, :any, required: true
  attr :participant_policy_form, :any, required: true
  attr :editing, :boolean, default: false
  attr :uploads, :map, required: true
  attr :instructor_options, :list, default: []
  attr :categories, :list, required: true, doc: "List of valid program categories"

  def program_form(assigns) do
    ~H"""
    <div class={["bg-white p-6 shadow-sm border border-hero-grey-200", Theme.rounded(:xl)]}>
      <div class="flex items-center justify-between mb-6">
        <h3 class="text-lg font-semibold text-hero-charcoal">
          <%= if @editing do %>
            {gettext("Edit Program")}
          <% else %>
            {gettext("New Program")}
          <% end %>
        </h3>
        <button
          type="button"
          phx-click="close_program_form"
          class="text-hero-grey-400 hover:text-hero-grey-600"
        >
          <.icon name="hero-x-mark-mini" class="w-5 h-5" />
        </button>
      </div>

      <.form
        for={@form}
        id="program-form"
        phx-change="validate_program"
        phx-submit="save_program"
        class="space-y-4"
      >
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <.input
            field={@form[:title]}
            type="text"
            label={gettext("Title")}
            placeholder={gettext("e.g., Art Adventures")}
            required
          />
          <.input
            field={@form[:category]}
            type="select"
            label={gettext("Category")}
            options={category_options(@categories)}
            prompt={gettext("Choose a category")}
            required
          />
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <.input
            field={@form[:price]}
            type="number"
            label={gettext("Price (EUR)")}
            placeholder="0.00"
            step="0.01"
            min="0"
            required
          />
          <.input
            field={@form[:location]}
            type="text"
            label={gettext("Location")}
            placeholder={gettext("e.g., Community Center, Main St")}
          />
        </div>

        <%!-- Schedule Section --%>
        <div class="space-y-3">
          <p class="text-sm font-semibold text-hero-charcoal">{gettext("Schedule (optional)")}</p>

          <%!-- Meeting Days Checkboxes --%>
          <fieldset id="meeting-days-fieldset">
            <legend class="text-sm text-hero-grey-600 mb-2">{gettext("Meeting Days")}</legend>
            <div class="flex flex-wrap gap-2">
              <label
                :for={day <- ~w(Monday Tuesday Wednesday Thursday Friday Saturday Sunday)}
                class={[
                  "inline-flex items-center gap-1.5 px-3 py-1.5 border text-sm cursor-pointer",
                  Theme.rounded(:lg),
                  Theme.transition(:normal),
                  "has-[:checked]:bg-hero-yellow has-[:checked]:border-hero-yellow-dark has-[:checked]:font-semibold",
                  "border-hero-grey-300 hover:border-hero-grey-400"
                ]}
              >
                <input
                  type="checkbox"
                  name="program_schema[meeting_days][]"
                  value={day}
                  checked={day in (Phoenix.HTML.Form.input_value(@form, :meeting_days) || [])}
                  class="sr-only"
                />
                {String.slice(day, 0, 3)}
              </label>
            </div>
            <%!-- Hidden input ensures empty array submitted when no days checked --%>
            <input type="hidden" name="program_schema[meeting_days][]" value="" />
          </fieldset>

          <%!-- Time Inputs --%>
          <div class="grid grid-cols-2 gap-4">
            <.input
              field={@form[:meeting_start_time]}
              type="time"
              label={gettext("Start Time")}
            />
            <.input
              field={@form[:meeting_end_time]}
              type="time"
              label={gettext("End Time")}
            />
          </div>

          <%!-- Date Inputs --%>
          <div class="grid grid-cols-2 gap-4">
            <.input
              field={@form[:start_date]}
              type="date"
              label={gettext("Start Date")}
            />
            <.input
              field={@form[:end_date]}
              type="date"
              label={gettext("End Date")}
            />
          </div>
        </div>

        <%!-- Registration Period Section --%>
        <div class="space-y-3">
          <p class="text-sm font-semibold text-hero-charcoal">
            {gettext("Registration Period (optional)")}
          </p>
          <p class="text-xs text-hero-grey-500">
            {gettext("Leave blank for open registration at any time.")}
          </p>
          <div class="grid grid-cols-2 gap-4">
            <.input
              field={@form[:registration_start_date]}
              type="date"
              label={gettext("Registration Opens")}
            />
            <.input
              field={@form[:registration_end_date]}
              type="date"
              label={gettext("Registration Closes")}
            />
          </div>
        </div>

        <%!-- Enrollment Capacity Section --%>
        <div class="space-y-3">
          <p class="text-sm font-semibold text-hero-charcoal">
            {gettext("Enrollment Capacity (optional)")}
          </p>
          <p class="text-xs text-hero-grey-500">
            {gettext("Set minimum and maximum enrollment for this program.")}
          </p>
          <div class="grid grid-cols-2 gap-4">
            <.input
              field={@enrollment_form[:min_enrollment]}
              type="number"
              label={gettext("Minimum Enrollment")}
              min="1"
            />
            <.input
              field={@enrollment_form[:max_enrollment]}
              type="number"
              label={gettext("Maximum Enrollment")}
              min="1"
            />
          </div>
        </div>

        <%!-- Participant Restrictions Section --%>
        <div class="space-y-4">
          <div>
            <p class="text-sm font-semibold text-hero-charcoal">
              {gettext("Participant Restrictions (optional)")}
            </p>
            <p class="text-xs text-hero-grey-500">
              {gettext("Define age, gender, or grade restrictions for eligible participants.")}
            </p>
          </div>

          <%!-- Eligibility Timing --%>
          <fieldset id="eligibility-at-fieldset">
            <legend class="text-sm text-hero-grey-600 mb-2">
              {gettext("Check eligibility at")}
            </legend>
            <div class="flex gap-4">
              <label class="flex items-center gap-2 text-sm">
                <input
                  type="radio"
                  name="participant_policy[eligibility_at]"
                  value="registration"
                  checked={
                    Phoenix.HTML.Form.input_value(@participant_policy_form, :eligibility_at) in [
                      "registration",
                      nil
                    ]
                  }
                  class="border-hero-grey-300 text-hero-cyan focus:ring-hero-cyan"
                />
                {gettext("Registration")}
              </label>
              <label class="flex items-center gap-2 text-sm">
                <input
                  type="radio"
                  name="participant_policy[eligibility_at]"
                  value="program_start"
                  checked={
                    Phoenix.HTML.Form.input_value(@participant_policy_form, :eligibility_at) ==
                      "program_start"
                  }
                  class="border-hero-grey-300 text-hero-cyan focus:ring-hero-cyan"
                />
                {gettext("Program Start")}
              </label>
            </div>
          </fieldset>

          <%!-- Age Restriction --%>
          <div class="grid grid-cols-2 gap-4">
            <.input
              field={@participant_policy_form[:min_age_months]}
              type="number"
              label={gettext("Minimum Age (months)")}
              min="0"
            />
            <.input
              field={@participant_policy_form[:max_age_months]}
              type="number"
              label={gettext("Maximum Age (months)")}
              min="0"
            />
          </div>

          <%!-- Gender Restriction --%>
          <fieldset id="allowed-genders-fieldset">
            <legend class="text-sm text-hero-grey-600 mb-2">
              {gettext("Allowed Genders")}
            </legend>
            <p class="text-xs text-hero-grey-400 mb-2">
              {gettext("Leave unchecked to allow all genders.")}
            </p>
            <div class="flex flex-wrap gap-3">
              <label
                :for={
                  {value, label} <- [
                    {"male", gettext("Male")},
                    {"female", gettext("Female")},
                    {"diverse", gettext("Diverse")},
                    {"not_specified", gettext("Not specified")}
                  ]
                }
                class="flex items-center gap-2 text-sm"
              >
                <input
                  type="checkbox"
                  name="participant_policy[allowed_genders][]"
                  value={value}
                  checked={
                    value in (Phoenix.HTML.Form.input_value(
                                @participant_policy_form,
                                :allowed_genders
                              ) ||
                                [])
                  }
                  class="rounded border-hero-grey-300 text-hero-cyan focus:ring-hero-cyan"
                />
                {label}
              </label>
            </div>
            <%!-- Hidden input ensures empty array submitted when no genders checked --%>
            <input type="hidden" name="participant_policy[allowed_genders][]" value="" />
          </fieldset>

          <%!-- Grade Restriction --%>
          <div class="grid grid-cols-2 gap-4">
            <.input
              field={@participant_policy_form[:min_grade]}
              type="select"
              label={gettext("Minimum Grade")}
              options={grade_options()}
              prompt={gettext("No minimum")}
            />
            <.input
              field={@participant_policy_form[:max_grade]}
              type="select"
              label={gettext("Maximum Grade")}
              options={grade_options()}
              prompt={gettext("No maximum")}
            />
          </div>
        </div>

        <.input
          field={@form[:description]}
          type="textarea"
          label={gettext("Description")}
          placeholder={gettext("Describe your program...")}
          rows="3"
          required
        />

        <%!-- Cover Image Upload --%>
        <div>
          <label class="block text-sm font-semibold text-hero-charcoal mb-2">
            {gettext("Cover Image")}
          </label>
          <div
            id="program-cover-upload"
            class={[
              "border-2 border-dashed border-hero-grey-300 p-4 text-center",
              Theme.rounded(:lg)
            ]}
            phx-drop-target={@uploads.program_cover.ref}
          >
            <div :for={entry <- @uploads.program_cover.entries} class="mb-3">
              <.live_img_preview
                entry={entry}
                class="w-full max-w-xs mx-auto rounded-lg object-cover"
              />
              <p class="text-sm text-hero-grey-500 mt-1">{entry.client_name}</p>
              <button
                type="button"
                phx-click="cancel_upload"
                phx-value-ref={entry.ref}
                phx-value-upload="program_cover"
                class="text-xs text-red-500 hover:text-red-700 mt-1"
              >
                {gettext("Remove")}
              </button>
              <div
                :for={err <- upload_errors(@uploads.program_cover, entry)}
                class="text-xs text-red-500 mt-1"
              >
                {upload_error_to_string(err)}
              </div>
            </div>

            <.live_file_input upload={@uploads.program_cover} class="hidden" />
            <label
              for={@uploads.program_cover.ref}
              class={[
                "inline-flex items-center gap-2 px-4 py-2 border border-hero-grey-300",
                "bg-white hover:bg-hero-grey-50 text-hero-charcoal text-sm font-medium cursor-pointer",
                Theme.rounded(:lg),
                Theme.transition(:normal)
              ]}
            >
              <.icon name="hero-photo-mini" class="w-4 h-4" />
              {gettext("Choose Image")}
            </label>
            <p class="text-xs text-hero-grey-400 mt-2">
              {gettext("JPG, PNG or WebP. Max 2MB.")}
            </p>
          </div>
        </div>

        <%!-- Assign Instructor --%>
        <.input
          field={@form[:instructor_id]}
          type="select"
          label={gettext("Assign Instructor")}
          options={@instructor_options}
          prompt={gettext("None (optional)")}
        />

        <div class="flex justify-end gap-3 pt-2">
          <button
            type="button"
            phx-click="close_program_form"
            class={[
              "px-4 py-2 border border-hero-grey-300 text-hero-charcoal",
              Theme.rounded(:lg),
              Theme.transition(:normal),
              "hover:bg-hero-grey-50"
            ]}
          >
            {gettext("Cancel")}
          </button>
          <button
            type="submit"
            id="save-program-btn"
            class={[
              "flex items-center gap-2 px-6 py-2.5 bg-hero-yellow hover:bg-hero-yellow-dark",
              "text-hero-charcoal font-semibold",
              Theme.rounded(:lg),
              Theme.transition(:normal)
            ]}
          >
            <.icon name="hero-check-mini" class="w-5 h-5" />
            {gettext("Save Program")}
          </button>
        </div>
      </.form>
    </div>
    """
  end

  defp category_options(categories) do
    Enum.map(categories, fn cat -> {String.capitalize(cat), cat} end)
  end

  defp grade_options do
    Enum.map(1..13, fn grade -> {"Klasse #{grade}", to_string(grade)} end)
  end

  @doc """
  Renders an "Add" card with dashed border.

  ## Examples

      <.add_card_button label="Add Team Member" icon="hero-user-plus-mini" />
  """
  attr :label, :string, required: true
  attr :icon, :string, default: "hero-plus-mini"
  attr :class, :string, default: ""
  attr :rest, :global, include: ~w(phx-click)

  def add_card_button(assigns) do
    ~H"""
    <button
      type="button"
      class={[
        "w-full h-full min-h-[200px] border-2 border-dashed border-hero-grey-300",
        "flex flex-col items-center justify-center gap-2",
        "text-hero-grey-400 hover:border-hero-cyan hover:text-hero-cyan active:scale-[0.98]",
        Theme.rounded(:xl),
        Theme.transition(:normal),
        @class
      ]}
      {@rest}
    >
      <.icon name={@icon} class="w-8 h-8" />
      <span class="font-medium">{@label}</span>
    </button>
    """
  end

  @doc """
  Renders the programs table with search and filters.

  ## Examples

      <.programs_table
        programs={@programs}
        staff_options={@staff_options}
        search_query=""
        selected_staff="all"
      />
  """
  attr :programs, :any, required: true, doc: "LiveView stream of programs"
  attr :staff_options, :list, required: true
  attr :search_query, :string, default: ""
  attr :selected_staff, :string, default: "all"

  def programs_table(assigns) do
    ~H"""
    <div class={["bg-white shadow-sm border border-hero-grey-200", Theme.rounded(:xl)]}>
      <div class="p-4 border-b border-hero-grey-200">
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <h3 class="text-lg font-semibold text-hero-charcoal">
            {gettext("Program Inventory")}
          </h3>
          <div class="flex flex-col sm:flex-row gap-2">
            <div class="relative">
              <.icon
                name="hero-magnifying-glass-mini"
                class="w-5 h-5 text-hero-grey-400 absolute left-3 top-1/2 -translate-y-1/2"
              />
              <input
                type="text"
                name="search"
                value={@search_query}
                placeholder={gettext("Search by name...")}
                class={[
                  "pl-10 pr-4 py-2 w-full sm:w-64 border border-hero-grey-300 bg-white",
                  "text-sm placeholder-hero-grey-400 focus:border-hero-cyan focus:ring-1 focus:ring-hero-cyan",
                  Theme.rounded(:lg)
                ]}
                phx-change="search_programs"
                phx-debounce="300"
              />
            </div>
            <div class="relative">
              <.icon
                name="hero-funnel-mini"
                class="w-5 h-5 text-hero-grey-400 absolute left-3 top-1/2 -translate-y-1/2"
              />
              <select
                name="staff_filter"
                class={[
                  "pl-10 pr-8 py-2 w-full sm:w-40 border border-hero-grey-300 bg-white",
                  "text-sm focus:border-hero-cyan focus:ring-1 focus:ring-hero-cyan appearance-none",
                  Theme.rounded(:lg)
                ]}
                phx-change="filter_by_staff"
              >
                <option
                  :for={option <- @staff_options}
                  value={option.value}
                  selected={option.value == @selected_staff}
                >
                  {option.label}
                </option>
              </select>
            </div>
          </div>
        </div>
      </div>

      <div class="overflow-x-auto">
        <table class="w-full">
          <thead class="bg-hero-grey-50 border-b border-hero-grey-200">
            <tr>
              <th class="px-4 py-3 text-left text-xs font-semibold text-hero-grey-500 uppercase tracking-wider">
                {gettext("Program Name")}
              </th>
              <th class="px-4 py-3 text-left text-xs font-semibold text-hero-grey-500 uppercase tracking-wider">
                {gettext("Assigned Staff")}
              </th>
              <th class="px-4 py-3 text-left text-xs font-semibold text-hero-grey-500 uppercase tracking-wider">
                {gettext("Status")}
              </th>
              <th class="px-4 py-3 text-left text-xs font-semibold text-hero-grey-500 uppercase tracking-wider">
                {gettext("Enrollment")}
              </th>
              <th class="px-4 py-3 text-right text-xs font-semibold text-hero-grey-500 uppercase tracking-wider">
                {gettext("Actions")}
              </th>
            </tr>
          </thead>
          <tbody id="programs-table-body" phx-update="stream" class="divide-y divide-hero-grey-200">
            <tr :for={{dom_id, program} <- @programs} id={dom_id} class="hover:bg-hero-grey-50">
              <td class="px-4 py-4">
                <div class="font-medium text-hero-charcoal">{program.name}</div>
                <div class="text-sm text-hero-grey-500">
                  {program.category} • €{program.price}
                </div>
              </td>
              <td class="px-4 py-4">
                <div :if={program.assigned_staff} class="flex items-center gap-2">
                  <div class={[
                    "w-8 h-8 flex items-center justify-center text-white text-xs font-medium",
                    Theme.rounded(:full),
                    Theme.gradient(:primary)
                  ]}>
                    {program.assigned_staff.initials}
                  </div>
                  <span class="text-sm text-hero-charcoal">{program.assigned_staff.name}</span>
                </div>
                <span :if={!program.assigned_staff} class="text-sm text-hero-grey-400 italic">
                  {gettext("Unassigned")}
                </span>
              </td>
              <td class="px-4 py-4">
                <.status_pill color={status_color(program.status)}>
                  {status_label(program.status)}
                </.status_pill>
              </td>
              <td class="px-4 py-4">
                <div class="flex items-center gap-3">
                  <div class="w-24 h-2 bg-hero-grey-200 rounded-full overflow-hidden">
                    <div
                      class="h-full bg-hero-cyan rounded-full"
                      style={"width: #{enrollment_percentage(program)}%"}
                    >
                    </div>
                  </div>
                  <span class="text-sm text-hero-grey-600">
                    {format_enrollment_count(program.enrolled)}/{format_enrollment_count(
                      program.capacity
                    )}
                  </span>
                </div>
              </td>
              <td class="px-4 py-4">
                <div class="flex items-center justify-end gap-1">
                  <.link navigate={~p"/programs/#{program.id}"} class="inline-block">
                    <.action_button icon="hero-eye-mini" title={gettext("Preview")} />
                  </.link>
                  <.action_button
                    icon="hero-calendar-days"
                    title={gettext("View sessions")}
                    phx-click="view_sessions"
                    phx-value-program-id={program.id}
                  />
                  <.action_button
                    id={"view-roster-#{program.id}"}
                    icon="hero-user-group-mini"
                    title={gettext("View Roster")}
                    phx-click="view_roster"
                    phx-value-id={program.id}
                  />
                  <.action_button
                    icon="hero-pencil-square-mini"
                    title={gettext("Edit")}
                    phx-click="edit_program"
                    phx-value-id={program.id}
                  />
                  <.link
                    navigate={~p"/provider/incidents/new?program_id=#{program.id}"}
                    class="inline-block"
                  >
                    <.action_button
                      icon="hero-exclamation-triangle-mini"
                      title={gettext("Report Incident")}
                    />
                  </.link>
                  <.link
                    navigate={~p"/provider/programs/#{program.id}/incidents"}
                    class="inline-block"
                  >
                    <.action_button
                      icon="hero-document-text-mini"
                      title={gettext("Incident Reports")}
                    />
                  </.link>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp status_color(:active), do: "success"
  defp status_color(:pending), do: "warning"
  defp status_color(:inactive), do: "error"
  defp status_color(_), do: "info"

  defp status_label(:active), do: gettext("Active")
  defp status_label(:pending), do: gettext("Pending")
  defp status_label(:inactive), do: gettext("Inactive")
  defp status_label(_), do: gettext("Unknown")

  defp enrollment_percentage(%{enrolled: e, capacity: c}) when is_integer(e) and is_integer(c) and c > 0 do
    min(100, div(e * 100, c))
  end

  defp enrollment_percentage(_), do: 0

  defp format_enrollment_count(nil), do: "\u2014"
  defp format_enrollment_count(count), do: to_string(count)

  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :disabled, :boolean, default: false
  attr :rest, :global, include: ~w(id phx-click phx-value-id phx-value-program-id)

  defp action_button(assigns) do
    ~H"""
    <button
      type="button"
      title={@title}
      aria-label={@title}
      disabled={@disabled}
      class={[
        "p-2",
        Theme.rounded(:lg),
        Theme.transition(:normal),
        if(@disabled,
          do: "text-hero-grey-300 cursor-not-allowed",
          else: "text-hero-grey-400 hover:text-hero-charcoal hover:bg-hero-grey-100"
        )
      ]}
      {@rest}
    >
      <.icon name={@icon} class="w-5 h-5" />
    </button>
    """
  end

  @doc """
  Renders a tabbed modal displaying the enrollment roster and invites for a program.
  Shows enrolled tab (child name, status, date) and invites tab (invites table, CSV upload).
  """
  attr :program_name, :string, required: true
  attr :program_id, :string, required: true
  attr :entries, :list, required: true
  attr :invites, :list, required: true
  attr :active_tab, :string, default: "enrolled"
  attr :enrolled_count, :integer, default: 0
  attr :invite_count, :integer, default: 0
  attr :uploads, :map, required: true
  attr :import_errors, :any, default: nil
  attr :can_message?, :boolean, default: false
  attr :invite_mode, :string, default: "single"
  attr :single_invite_form, :any, default: nil

  def roster_modal(assigns) do
    ~H"""
    <div
      id="roster-modal"
      class="fixed inset-0 z-50 overflow-y-auto"
      role="dialog"
      aria-modal="true"
      phx-window-keydown="close_roster"
      phx-key="Escape"
    >
      <div class="flex min-h-screen items-center justify-center p-4">
        <div class="fixed inset-0 bg-black/50" phx-click="close_roster"></div>
        <div class={[
          "relative bg-white w-full max-w-2xl shadow-xl",
          Theme.rounded(:xl)
        ]}>
          <%!-- Header --%>
          <div class="flex items-center justify-between p-4 border-b border-hero-grey-200">
            <h3 class="text-lg font-semibold text-hero-charcoal">
              {gettext("Roster: %{name}", name: @program_name)}
            </h3>
            <div class="flex items-center gap-1">
              <%!-- Trigger: provider wants to broadcast to enrolled parents
                   Why: navigates to existing BroadcastLive page with program context
                   Outcome: disabled with title attribute when no parents enrolled --%>
              <%= if @enrolled_count > 0 do %>
                <.link
                  id={"broadcast-#{@program_id}"}
                  navigate={~p"/provider/programs/#{@program_id}/broadcast"}
                  title={gettext("Send Broadcast")}
                  aria-label={gettext("Send Broadcast")}
                  class={[
                    "p-2",
                    Theme.rounded(:lg),
                    Theme.transition(:normal),
                    "text-hero-grey-400 hover:text-hero-charcoal hover:bg-hero-grey-100"
                  ]}
                >
                  <.icon name="hero-megaphone-mini" class="w-5 h-5" />
                </.link>
              <% else %>
                <.action_button
                  id={"broadcast-#{@program_id}"}
                  icon="hero-megaphone-mini"
                  title={gettext("No enrolled parents")}
                  disabled={true}
                />
              <% end %>
              <button
                type="button"
                phx-click="close_roster"
                aria-label={gettext("close")}
                class="text-hero-grey-400 hover:text-hero-grey-600"
              >
                <.icon name="hero-x-mark-mini" class="w-5 h-5" />
              </button>
            </div>
          </div>

          <%!-- Tabs --%>
          <div class="flex border-b border-hero-grey-200" role="tablist">
            <button
              id="roster-tab-enrolled"
              type="button"
              role="tab"
              aria-selected={to_string(@active_tab == "enrolled")}
              phx-click="switch_roster_tab"
              phx-value-tab="enrolled"
              class={[
                "px-4 py-3 text-sm font-medium border-b-2 -mb-px",
                if(@active_tab == "enrolled",
                  do: "border-hero-primary text-hero-primary",
                  else: "border-transparent text-hero-grey-500 hover:text-hero-charcoal"
                )
              ]}
            >
              {gettext("Enrolled (%{count})", count: @enrolled_count)}
            </button>
            <button
              id="roster-tab-invites"
              type="button"
              role="tab"
              aria-selected={to_string(@active_tab == "invites")}
              phx-click="switch_roster_tab"
              phx-value-tab="invites"
              class={[
                "px-4 py-3 text-sm font-medium border-b-2 -mb-px",
                if(@active_tab == "invites",
                  do: "border-hero-primary text-hero-primary",
                  else: "border-transparent text-hero-grey-500 hover:text-hero-charcoal"
                )
              ]}
            >
              {gettext("Invites (%{count})", count: @invite_count)}
            </button>
          </div>

          <%!-- Tab Content --%>
          <div class="p-4">
            <%= if @active_tab == "enrolled" do %>
              <div id="enrolled-tab-content">
                <.enrolled_tab entries={@entries} can_message?={@can_message?} />
              </div>
            <% else %>
              <div id="invites-tab-content">
                <.invites_tab
                  invites={@invites}
                  program_id={@program_id}
                  uploads={@uploads}
                  import_errors={@import_errors}
                  invite_mode={@invite_mode}
                  single_invite_form={@single_invite_form}
                />
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a modal listing every session of a program with date/time, assigned
  staff, cover staff (reserved), attendance count, and status.

  ## Example

      <.sessions_modal :if={@sessions_modal} modal={@sessions_modal} />
  """
  attr :modal, :map, required: true

  def sessions_modal(assigns) do
    ~H"""
    <div
      id="sessions-modal"
      role="dialog"
      aria-modal="true"
      aria-labelledby="sessions-modal-title"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
      phx-window-keydown="close_sessions"
      phx-key="escape"
    >
      <div
        class="bg-white rounded-lg shadow-xl max-w-4xl w-full max-h-[80vh] overflow-hidden flex flex-col"
        phx-click-away="close_sessions"
      >
        <div class="flex items-center justify-between px-6 py-4 border-b">
          <h2 id="sessions-modal-title" class={Theme.typography(:section_title)}>
            {gettext("Sessions — %{title}", title: @modal.program_title)}
          </h2>
          <button type="button" phx-click="close_sessions" aria-label={gettext("Close")}>
            <.icon name="hero-x-mark" class="w-5 h-5" />
          </button>
        </div>

        <div class="flex-1 overflow-y-auto">
          <%= if @modal.sessions == [] do %>
            <div class="text-center py-12">
              <.icon name="hero-calendar-days" class="w-12 h-12 text-hero-grey-300 mx-auto" />
              <p class="mt-4 text-hero-grey-500">{gettext("No sessions scheduled yet.")}</p>
            </div>
          <% else %>
            <table class="w-full text-sm">
              <thead class="bg-hero-grey-50 text-left">
                <tr>
                  <th class="px-4 py-3">{gettext("Date / time")}</th>
                  <th class="px-4 py-3">{gettext("Assigned staff")}</th>
                  <th class="px-4 py-3">{gettext("Cover")}</th>
                  <th class="px-4 py-3">{gettext("Attendance")}</th>
                  <th class="px-4 py-3">{gettext("Status")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={s <- @modal.sessions} class="border-t">
                  <td class="px-4 py-3">
                    {Calendar.strftime(s.session_date, "%a, %d %b")}
                    <span class="text-hero-grey-500">
                      · {Calendar.strftime(s.start_time, "%H:%M")}–{Calendar.strftime(
                        s.end_time,
                        "%H:%M"
                      )}
                    </span>
                  </td>
                  <td class="px-4 py-3">
                    {s.current_assigned_staff_name || gettext("Unassigned")}
                  </td>
                  <td class="px-4 py-3 text-hero-grey-500">
                    {s.cover_staff_name || "—"}
                  </td>
                  <td class="px-4 py-3">
                    <span :if={s.status != :cancelled}>
                      {s.checked_in_count} / {s.total_count}
                    </span>
                  </td>
                  <td class="px-4 py-3">
                    <.participation_status status={s.status} size={:sm} />
                  </td>
                </tr>
              </tbody>
            </table>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :entries, :list, required: true
  attr :can_message?, :boolean, default: false

  defp enrolled_tab(assigns) do
    ~H"""
    <div :if={@entries == []} id="roster-empty" class="text-center py-8">
      <.icon name="hero-user-group" class="w-12 h-12 mx-auto text-hero-grey-300 mb-3" />
      <p class="text-hero-grey-500">{gettext("No enrollments yet.")}</p>
    </div>

    <table :if={@entries != []} id="roster-table" class="w-full">
      <thead class="bg-hero-grey-50 border-b border-hero-grey-200">
        <tr>
          <th class="px-3 py-2 text-left text-xs font-semibold text-hero-grey-500 uppercase">
            {gettext("Child Name")}
          </th>
          <th class="px-3 py-2 text-left text-xs font-semibold text-hero-grey-500 uppercase">
            {gettext("Status")}
          </th>
          <th class="px-3 py-2 text-left text-xs font-semibold text-hero-grey-500 uppercase">
            {gettext("Enrolled")}
          </th>
          <th class="px-3 py-2 text-right text-xs font-semibold text-hero-grey-500 uppercase">
            <span class="sr-only">{gettext("Actions")}</span>
          </th>
        </tr>
      </thead>
      <tbody class="divide-y divide-hero-grey-200">
        <tr :for={entry <- @entries} class="hover:bg-hero-grey-50">
          <td class="px-3 py-3 text-sm text-hero-charcoal font-medium">
            {entry.child_name}
          </td>
          <td class="px-3 py-3">
            <.status_pill color={enrollment_status_color(entry.status)}>
              {enrollment_status_label(entry.status)}
            </.status_pill>
          </td>
          <td class="px-3 py-3 text-sm text-hero-grey-500">
            {format_enrollment_date(entry.enrolled_at)}
          </td>
          <td class="px-3 py-3 text-right">
            <%!-- Trigger: can_message? is true AND enrollment is confirmed AND parent has a user account
                 Why: only entitled providers can message confirmed enrollments with linked parents
                 Outcome: enabled button fires send_message_to_parent event; otherwise disabled with explanation --%>
            <%= if @can_message? and entry.status == :confirmed and entry.parent_user_id do %>
              <button
                id={"send-message-#{entry.enrollment_id}"}
                type="button"
                phx-click="send_message_to_parent"
                phx-value-parent-user-id={entry.parent_user_id}
                title={gettext("Send Message")}
                aria-label={gettext("Send Message")}
                class={[
                  "p-2 inline-flex",
                  Theme.rounded(:lg),
                  Theme.transition(:normal),
                  "text-hero-grey-400 hover:text-hero-charcoal hover:bg-hero-grey-100"
                ]}
              >
                <.icon name="hero-chat-bubble-left-mini" class="w-5 h-5" />
              </button>
            <% else %>
              <button
                id={"send-message-#{entry.enrollment_id}"}
                type="button"
                disabled
                title={message_button_title(entry)}
                aria-label={message_button_title(entry)}
                class={[
                  "p-2 inline-flex",
                  Theme.rounded(:lg),
                  "text-hero-grey-300 cursor-not-allowed"
                ]}
              >
                <.icon name="hero-chat-bubble-left-mini" class="w-5 h-5" />
              </button>
            <% end %>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  defp message_button_title(entry) do
    cond do
      entry.parent_user_id == nil -> gettext("Parent account not available")
      entry.status != :confirmed -> gettext("Enrollment not confirmed")
      true -> gettext("Send Message")
    end
  end

  attr :invites, :list, required: true
  attr :program_id, :string, required: true
  attr :uploads, :map, required: true
  attr :import_errors, :any, default: nil
  attr :invite_mode, :string, default: "single"
  attr :single_invite_form, :any, default: nil

  defp invites_tab(assigns) do
    ~H"""
    <div>
      <%!-- Two mutually-exclusive toggle buttons, not a true tablist.
            Uses role=group + aria-pressed rather than role=tablist/tab
            because the content panels aren't siblings — they replace each
            other — so aria-controls/tabpanel wiring would be misleading. --%>
      <div
        id="invite-mode-toggle"
        role="group"
        aria-label={gettext("Invite mode")}
        class="flex flex-col sm:flex-row gap-2 mb-5 sm:max-w-md"
      >
        <button
          id="invite-mode-single"
          type="button"
          aria-pressed={to_string(@invite_mode == "single")}
          phx-click="switch_invite_mode"
          phx-value-mode="single"
          class={[
            "flex-1 px-4 py-2 text-sm font-medium border text-center",
            Theme.rounded(:lg),
            Theme.transition(:normal),
            if(@invite_mode == "single",
              do: "border-hero-primary bg-hero-primary/5 text-hero-primary",
              else: "border-hero-grey-300 text-hero-grey-600 hover:bg-hero-grey-50"
            )
          ]}
        >
          {gettext("Invite one person")}
        </button>
        <button
          id="invite-mode-csv"
          type="button"
          aria-pressed={to_string(@invite_mode == "csv")}
          phx-click="switch_invite_mode"
          phx-value-mode="csv"
          class={[
            "flex-1 px-4 py-2 text-sm font-medium border text-center",
            Theme.rounded(:lg),
            Theme.transition(:normal),
            if(@invite_mode == "csv",
              do: "border-hero-primary bg-hero-primary/5 text-hero-primary",
              else: "border-hero-grey-300 text-hero-grey-600 hover:bg-hero-grey-50"
            )
          ]}
        >
          {gettext("Upload a list")}
        </button>
      </div>

      <%= if @invite_mode == "single" and @single_invite_form do %>
        <.single_invite_form form={@single_invite_form} program_id={@program_id} />
      <% else %>
        <div class="flex items-center gap-3 mb-4">
          <form
            id="csv-upload-form"
            phx-change="validate_csv_upload"
            phx-submit="import_csv"
            class="inline"
          >
            <label
              for={@uploads.csv_file.ref}
              class={[
                "inline-flex items-center gap-2 px-4 py-2 text-sm font-medium text-white cursor-pointer",
                Theme.rounded(:lg),
                Theme.gradient(:primary)
              ]}
            >
              <.icon name="hero-arrow-up-tray-mini" class="w-4 h-4" />
              {gettext("Upload CSV")}
            </label>
            <.live_file_input upload={@uploads.csv_file} class="hidden" />

            <%!-- Show selected file + import button --%>
            <div :for={entry <- @uploads.csv_file.entries} class="mt-3 flex items-center gap-3">
              <span class="text-sm text-hero-charcoal">{entry.client_name}</span>
              <button
                type="submit"
                class={[
                  "px-3 py-1.5 text-sm font-medium text-white",
                  Theme.rounded(:lg),
                  Theme.gradient(:primary)
                ]}
              >
                {gettext("Import")}
              </button>
              <button
                type="button"
                phx-click="cancel_csv_upload"
                phx-value-ref={entry.ref}
                class="text-sm text-hero-grey-500 hover:text-hero-charcoal"
              >
                {gettext("Cancel")}
              </button>
            </div>

            <%!-- Upload errors --%>
            <div :for={err <- upload_errors(@uploads.csv_file)} class="mt-2 text-sm text-red-600">
              {upload_error_to_string(err)}
            </div>
          </form>

          <a
            href="/downloads/enrollment-import-template.csv"
            download="enrollment-import-template.csv"
            class={[
              "inline-flex items-center gap-2 px-4 py-2 text-sm font-medium text-hero-grey-600",
              "border border-hero-grey-300 hover:bg-hero-grey-50",
              Theme.rounded(:lg)
            ]}
          >
            <.icon name="hero-arrow-down-tray-mini" class="w-4 h-4" />
            {gettext("Download Template")}
          </a>
        </div>

        <%!-- Import errors (CSV path only) --%>
        <div
          :if={@import_errors}
          id="import-errors"
          class={[
            "mt-3 p-3 bg-red-50 border border-red-200 text-sm text-red-700",
            Theme.rounded(:lg)
          ]}
        >
          <p class="font-semibold mb-2">{gettext("Rows with errors")}</p>
          <ul class="list-disc pl-5 space-y-1">
            <li :for={msg <- format_import_errors(@import_errors)}>
              {msg}
            </li>
          </ul>
        </div>
      <% end %>

      <%!-- Empty state --%>
      <div :if={@invites == []} id="invites-empty" class="text-center py-8">
        <.icon name="hero-envelope" class="w-12 h-12 mx-auto text-hero-grey-300 mb-3" />
        <p class="text-hero-grey-500">
          {gettext("No invites yet. Upload a CSV to invite families.")}
        </p>
      </div>

      <%!-- Invites table — scrollable container for mobile viewports --%>
      <div :if={@invites != []} class="overflow-x-auto -mx-4 px-4 sm:mx-0 sm:px-0">
        <table id="invites-table" class="w-full min-w-[500px]">
          <thead class="bg-hero-grey-50 border-b border-hero-grey-200">
            <tr>
              <th class="px-3 py-2 text-left text-xs font-semibold text-hero-grey-500 uppercase">
                {gettext("Child Name")}
              </th>
              <th class="px-3 py-2 text-left text-xs font-semibold text-hero-grey-500 uppercase">
                {gettext("Guardian Email")}
              </th>
              <th class="px-3 py-2 text-left text-xs font-semibold text-hero-grey-500 uppercase">
                {gettext("Status")}
              </th>
              <th class="px-3 py-2 text-right text-xs font-semibold text-hero-grey-500 uppercase">
                {gettext("Actions")}
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-hero-grey-200">
            <tr :for={invite <- @invites} id={"invite-#{invite.id}"} class="hover:bg-hero-grey-50">
              <td class="px-3 py-3 text-sm text-hero-charcoal font-medium">
                {invite.child_first_name} {invite.child_last_name}
              </td>
              <td class="px-3 py-3 text-sm text-hero-grey-500">
                {invite.guardian_email}
              </td>
              <td class="px-3 py-3">
                <.status_pill color={invite_status_color(invite.status)}>
                  {invite_status_label(invite.status)}
                </.status_pill>
              </td>
              <td class="px-3 py-3 text-right">
                <div class="flex items-center justify-end gap-1">
                  <.action_button
                    :if={invite.status in [:pending, :invite_sent, :failed]}
                    icon="hero-arrow-path-mini"
                    title={gettext("Resend Invite")}
                    phx-click="resend_invite"
                    phx-value-id={invite.id}
                  />
                  <.action_button
                    :if={invite.status in [:pending, :invite_sent, :failed]}
                    icon="hero-trash-mini"
                    title={gettext("Remove")}
                    phx-click="delete_invite"
                    phx-value-id={invite.id}
                  />
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  @doc false
  attr :form, :any, required: true
  attr :program_id, :string, required: true

  defp single_invite_form(assigns) do
    ~H"""
    <.form
      id="single-invite-form"
      for={@form}
      phx-change="validate_single_invite"
      phx-submit="submit_single_invite"
      class="space-y-6"
    >
      <%!-- Program is implicit from the roster modal; set as hidden so the
            changeset still casts and validates it. --%>
      <input type="hidden" name={@form[:program_id].name} value={@program_id} />

      <section aria-labelledby="single-invite-child-heading">
        <h4
          id="single-invite-child-heading"
          class={[Theme.typography(:card_title), "mb-3 text-hero-charcoal"]}
        >
          {gettext("Child")}
        </h4>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <.input field={@form[:child_first_name]} label={gettext("First name")} required />
          <.input field={@form[:child_last_name]} label={gettext("Last name")} required />
          <div class="md:col-span-2">
            <.input
              field={@form[:child_date_of_birth]}
              type="date"
              label={gettext("Date of birth")}
              required
            />
          </div>
        </div>
      </section>

      <section aria-labelledby="single-invite-guardian-heading">
        <h4
          id="single-invite-guardian-heading"
          class={[Theme.typography(:card_title), "mb-3 text-hero-charcoal"]}
        >
          {gettext("Primary guardian")}
        </h4>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div class="md:col-span-2">
            <.input
              field={@form[:guardian_email]}
              type="email"
              label={gettext("Email")}
              required
            />
          </div>
          <.input field={@form[:guardian_first_name]} label={gettext("First name")} />
          <.input field={@form[:guardian_last_name]} label={gettext("Last name")} />
        </div>
      </section>

      <section aria-labelledby="single-invite-guardian2-heading">
        <h4
          id="single-invite-guardian2-heading"
          class={[Theme.typography(:card_title), "mb-3 text-hero-charcoal"]}
        >
          {gettext("Second guardian (optional)")}
        </h4>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div class="md:col-span-2">
            <.input field={@form[:guardian2_email]} type="email" label={gettext("Email")} />
          </div>
          <.input field={@form[:guardian2_first_name]} label={gettext("First name")} />
          <.input field={@form[:guardian2_last_name]} label={gettext("Last name")} />
        </div>
      </section>

      <section aria-labelledby="single-invite-school-heading">
        <h4
          id="single-invite-school-heading"
          class={[Theme.typography(:card_title), "mb-3 text-hero-charcoal"]}
        >
          {gettext("School (optional)")}
        </h4>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <.input
            field={@form[:school_grade]}
            type="number"
            label={gettext("Grade")}
            min="1"
            max="13"
          />
          <.input field={@form[:school_name]} label={gettext("School name")} />
        </div>
      </section>

      <section aria-labelledby="single-invite-medical-heading">
        <h4
          id="single-invite-medical-heading"
          class={[Theme.typography(:card_title), "mb-3 text-hero-charcoal"]}
        >
          {gettext("Medical & consents (optional)")}
        </h4>
        <div class="space-y-3">
          <.input
            field={@form[:medical_conditions]}
            type="textarea"
            label={gettext("Medical conditions")}
          />
          <.input field={@form[:nut_allergy]} type="checkbox" label={gettext("Nut allergy")} />
          <.input
            field={@form[:consent_photo_marketing]}
            type="checkbox"
            label={gettext("Photos may appear in marketing materials")}
          />
          <.input
            field={@form[:consent_photo_social_media]}
            type="checkbox"
            label={gettext("Photos may appear on social media")}
          />
        </div>
      </section>

      <div class="flex justify-end pt-2">
        <button
          id="single-invite-submit"
          type="submit"
          phx-disable-with={gettext("Sending...")}
          class={[
            "inline-flex items-center gap-2 px-4 py-2 text-sm font-medium text-white",
            Theme.rounded(:lg),
            Theme.gradient(:primary)
          ]}
        >
          <.icon name="hero-paper-airplane-mini" class="w-4 h-4" />
          {gettext("Send invite")}
        </button>
      </div>
    </.form>
    """
  end

  defp enrollment_status_color(:pending), do: "warning"
  defp enrollment_status_color(:confirmed), do: "success"
  defp enrollment_status_color(_), do: "info"

  defp enrollment_status_label(:pending), do: gettext("Pending")
  defp enrollment_status_label(:confirmed), do: gettext("Confirmed")
  defp enrollment_status_label(status), do: status |> to_string() |> String.capitalize()

  defp format_enrollment_date(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %d, %Y")
  end

  defp format_enrollment_date(_), do: "\u2014"

  # Trigger: invite status values differ from enrollment status values
  # Why: invites follow their own lifecycle (pending → invite_sent → registered → enrolled)
  # Outcome: map each invite status to the correct status_pill color
  defp invite_status_color(:pending), do: "warning"
  defp invite_status_color(:invite_sent), do: "info"
  defp invite_status_color(:registered), do: "info"
  defp invite_status_color(:enrolled), do: "success"
  defp invite_status_color(:failed), do: "error"
  defp invite_status_color(_), do: "info"

  defp invite_status_label(:pending), do: gettext("Pending")
  defp invite_status_label(:invite_sent), do: gettext("Sent")
  defp invite_status_label(:registered), do: gettext("Registered")
  defp invite_status_label(:enrolled), do: gettext("Enrolled")
  defp invite_status_label(:failed), do: gettext("Failed")
  defp invite_status_label(status), do: status |> to_string() |> String.capitalize()

  # Partial-success path: list of row-level failure maps from ImportEnrollmentCsv
  defp format_import_errors(failures) when is_list(failures) do
    Enum.map(failures, fn %{row: row, category: category, errors: errors} ->
      row_label = if row, do: gettext("Row %{row}", row: row), else: gettext("Row —")
      category_label = category |> to_string() |> String.capitalize()
      error_detail = format_failure_errors(errors)
      "#{row_label} [#{category_label}]: #{error_detail}"
    end)
  end

  # Whole-file fatal path: map with parse_errors key
  defp format_import_errors(%{parse_errors: errs}) when is_list(errs) do
    Enum.map(errs, fn {_row, msg} -> msg end)
  end

  defp format_import_errors(_), do: [gettext("An unexpected error occurred during import.")]

  defp format_failure_errors(errors) when is_binary(errors), do: errors

  defp format_failure_errors(errors) when is_list(errors) do
    Enum.map_join(errors, ", ", fn {field, msg} -> "#{humanize_field(field)}: #{msg}" end)
  end

  # Trigger: each field atom needs a user-facing label
  # Why: dgettext calls must happen at runtime (not in module attributes) for i18n
  # Outcome: labels are translatable via the "enrollment" gettext domain
  defp humanize_field(:child_first_name), do: dgettext("enrollment", "Child first name")
  defp humanize_field(:child_last_name), do: dgettext("enrollment", "Child last name")
  defp humanize_field(:child_date_of_birth), do: dgettext("enrollment", "Date of birth")
  defp humanize_field(:guardian_email), do: dgettext("enrollment", "Guardian email")
  defp humanize_field(:guardian_first_name), do: dgettext("enrollment", "Guardian first name")
  defp humanize_field(:guardian_last_name), do: dgettext("enrollment", "Guardian last name")
  defp humanize_field(:guardian2_email), do: dgettext("enrollment", "Second guardian email")

  defp humanize_field(:guardian2_first_name), do: dgettext("enrollment", "Second guardian first name")

  defp humanize_field(:guardian2_last_name), do: dgettext("enrollment", "Second guardian last name")

  defp humanize_field(:program_name), do: dgettext("enrollment", "Program")
  defp humanize_field(:school_grade), do: dgettext("enrollment", "Grade")
  defp humanize_field(:school_name), do: dgettext("enrollment", "School")

  defp humanize_field(field) do
    field |> to_string() |> String.replace("_", " ") |> String.capitalize()
  end

  @doc """
  Converts a Phoenix upload error atom to a human-readable string.
  """
  def upload_error_to_string(:too_large), do: gettext("File is too large.")
  def upload_error_to_string(:too_many_files), do: gettext("Too many files.")
  def upload_error_to_string(:not_accepted), do: gettext("File type not accepted.")
  def upload_error_to_string(_), do: gettext("Upload error.")

  @doc """
  Renders the verification documents panel for the edit profile page.

  Includes the list of existing documents (as a stream) and the upload form.
  """
  attr :verification_docs, :any, required: true, doc: "LiveView stream of verification documents"
  attr :uploads, :map, required: true, doc: "The @uploads assign from the parent LiveView"
  attr :doc_type, :string, required: true, doc: "Currently selected document type"
  attr :document_types, :list, required: true, doc: "List of valid document types"

  def verification_documents_panel(assigns) do
    ~H"""
    <div class={["bg-white p-6 shadow-sm border border-hero-grey-200", Theme.rounded(:xl)]}>
      <h2 class="text-lg font-semibold text-hero-charcoal mb-4">
        {gettext("Verification Documents")}
      </h2>
      <p class="text-sm text-hero-grey-500 mb-6">
        {gettext("Upload documents to verify your business. Documents are reviewed by our team.")}
      </p>

      <%!-- Existing Documents --%>
      <div id="verification-docs" phx-update="stream" class="space-y-3 mb-6">
        <div id="vdoc-empty" class="hidden only:block text-sm text-hero-grey-400 italic py-4">
          {gettext("No documents uploaded yet.")}
        </div>
        <div
          :for={{id, doc} <- @verification_docs}
          id={id}
          class={[
            "flex items-center justify-between p-4 border border-hero-grey-200",
            Theme.rounded(:lg)
          ]}
        >
          <div class="flex items-center gap-3">
            <.icon name="hero-document-text-mini" class="w-5 h-5 text-hero-grey-400" />
            <div>
              <p class="text-sm font-medium text-hero-charcoal">
                {ProviderPresenter.document_type_label(doc.document_type)}
              </p>
              <p class="text-xs text-hero-grey-500">{doc.original_filename}</p>
            </div>
          </div>
          <.doc_status_badge status={doc.status} />
        </div>
      </div>

      <%!-- Upload New Document --%>
      <div class={[
        "border-t border-hero-grey-200 pt-6"
      ]}>
        <h3 class="text-sm font-semibold text-hero-charcoal mb-3">
          {gettext("Upload New Document")}
        </h3>

        <form
          id="doc-upload-form"
          phx-submit="upload_verification_doc"
          phx-change="validate_upload"
          class="space-y-4"
        >
          <div>
            <label class="block text-sm font-medium text-hero-grey-700 mb-1">
              {gettext("Document Type")}
            </label>
            <select
              name="doc_type"
              id="doc-type-select"
              phx-change="select_doc_type"
              class={[
                "w-full sm:w-64 px-3 py-2 border border-hero-grey-300 bg-white",
                "text-sm focus:border-hero-cyan focus:ring-1 focus:ring-hero-cyan",
                Theme.rounded(:lg)
              ]}
            >
              <option
                :for={type <- @document_types}
                value={type}
                selected={type == @doc_type}
              >
                {ProviderPresenter.document_type_label(type)}
              </option>
            </select>
          </div>

          <div>
            <.live_file_input upload={@uploads.verification_doc} class="hidden" />
            <label
              for={@uploads.verification_doc.ref}
              class={[
                "inline-flex items-center gap-2 px-4 py-2 border border-hero-grey-300",
                "bg-white hover:bg-hero-grey-50 text-hero-charcoal text-sm font-medium cursor-pointer",
                Theme.rounded(:lg),
                Theme.transition(:normal)
              ]}
            >
              <.icon name="hero-document-plus-mini" class="w-4 h-4" />
              {gettext("Select File")}
            </label>
            <p class="text-xs text-hero-grey-400 mt-2">
              {gettext("PDF, JPG or PNG. Max 10MB.")}
            </p>
            <div
              :for={entry <- @uploads.verification_doc.entries}
              class={[
                "flex items-center gap-3 mt-3 px-3 py-2 border border-hero-grey-200",
                "bg-hero-grey-50",
                Theme.rounded(:lg)
              ]}
            >
              <.icon name="hero-document-text-mini" class="w-5 h-5 text-hero-grey-500 shrink-0" />
              <span class="text-sm text-hero-charcoal truncate flex-1">{entry.client_name}</span>
              <button
                type="button"
                phx-click="cancel_upload"
                phx-value-ref={entry.ref}
                phx-value-upload="verification_doc"
                class="text-xs text-red-500 hover:text-red-700 shrink-0"
              >
                {gettext("Remove")}
              </button>
              <div
                :for={err <- upload_errors(@uploads.verification_doc, entry)}
                class="text-xs text-red-500"
              >
                {upload_error_to_string(err)}
              </div>
            </div>
          </div>

          <button
            type="submit"
            id="upload-doc-btn"
            disabled={@uploads.verification_doc.entries == []}
            class={[
              "flex items-center gap-2 px-4 py-2 border border-hero-grey-300",
              "bg-white hover:bg-hero-grey-50 text-hero-charcoal text-sm font-medium",
              "disabled:opacity-50 disabled:cursor-not-allowed",
              Theme.rounded(:lg),
              Theme.transition(:normal)
            ]}
          >
            <.icon name="hero-arrow-up-tray-mini" class="w-4 h-4" />
            {gettext("Upload Document")}
          </button>
        </form>
      </div>
    </div>
    """
  end
end
