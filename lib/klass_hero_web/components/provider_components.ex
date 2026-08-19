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

  alias KlassHero.Shared.ChangesetErrors
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
  Read-only pill for a Stripe Identity verification's `(status, outcome)`. Admins never
  override the outcome (ADR 0009), so this is display-only — there is no action affordance.
  """
  attr :status, :atom, required: true
  attr :outcome, :atom, default: nil

  def identity_status_badge(assigns) do
    {badge_class, label} = identity_status_style(assigns.status, assigns.outcome)
    assigns = assign(assigns, badge_class: badge_class, label: label)

    ~H"""
    <span class={["px-2.5 py-1 text-xs font-medium", Theme.rounded(:full), @badge_class]}>
      {@label}
    </span>
    """
  end

  defp identity_status_style(_status, :pass), do: {Theme.status_badge(:available), gettext("Passed")}
  defp identity_status_style(_status, :fail), do: {Theme.status_badge(:full), gettext("Failed")}
  defp identity_status_style(:processing, _outcome), do: {Theme.status_badge(:limited), gettext("In progress")}
  defp identity_status_style(_status, _outcome), do: {Theme.status_badge(:neutral), gettext("Pending")}

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
          navigate={~p"/provider/dashboard"}
          active={@current_tab == :overview}
          icon="hero-squares-2x2-mini"
        >
          {gettext("Overview")}
        </.nav_tab>
        <.nav_tab
          navigate={~p"/provider/dashboard/team"}
          active={@current_tab == :team}
          icon="hero-user-group-mini"
        >
          {gettext("Team & Profiles")}
        </.nav_tab>
        <.nav_tab
          navigate={~p"/provider/dashboard/programs"}
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
        "flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium",
        Theme.status_badge(:available),
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
        "flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium",
        Theme.status_badge(:limited),
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
        "flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium",
        Theme.status_badge(:full),
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
        "flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium",
        Theme.status_badge(:neutral),
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
    assigns = assign(assigns, :badge_class, invitation_status_badge_class(assigns.status))

    ~H"""
    <span class={[
      "shrink-0 px-2 py-0.5 text-xs font-medium",
      Theme.rounded(:full),
      @badge_class
    ]}>
      {@label}
    </span>
    """
  end

  # `:sent` (was blue) folds into `:neutral` — the filled token drops blue for
  # guaranteed WCAG AA contrast; the bordered `Theme.status/1` keeps `:info`.
  defp invitation_status_badge_class(:pending), do: Theme.status_badge(:limited)
  defp invitation_status_badge_class(:sent), do: Theme.status_badge(:neutral)
  defp invitation_status_badge_class(:accepted), do: Theme.status_badge(:available)
  defp invitation_status_badge_class(:failed), do: Theme.status_badge(:full)
  defp invitation_status_badge_class(:expired), do: Theme.status_badge(:neutral)
  defp invitation_status_badge_class(_), do: Theme.status_badge(:neutral)

  attr :icon, :string, required: true
  attr :label, :string, required: true

  defp verification_badge(assigns) do
    ~H"""
    <div class={[
      "flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium",
      Theme.status_badge(:neutral),
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
          <%!-- Ending employment is routine and reversible, so it reads as an
                ordinary action rather than a red destructive one. --%>
          <button
            type="button"
            id={"end-employment-#{@member.id}"}
            phx-click="end_employment"
            phx-value-id={@member.id}
            data-confirm={
              gettext(
                "%{name} will be unassigned from every program and removed from those conversations. Their history is kept and you can add them back later.",
                name: @member.full_name
              )
            }
            class={[
              "px-3 py-2 border border-hero-grey-300 bg-white",
              "hover:bg-hero-grey-50 text-hero-charcoal text-sm font-medium",
              Theme.rounded(:lg),
              Theme.transition(:normal)
            ]}
          >
            {gettext("Remove from team")}
          </button>
        </div>

        <%!-- Only rendered where the context would actually accept it: no linked
              account, no invitation ever sent, no program assignment ever. Absent
              rather than disabled — explaining a refusal for an action nobody was
              trying to take is clutter, and "Remove from team" is the answer for
              everyone else. --%>
        <button
          :if={@member.can_delete?}
          type="button"
          id={"delete-member-#{@member.id}"}
          phx-click="delete_member"
          phx-value-id={@member.id}
          data-confirm={
            gettext(
              "This deletes %{name} permanently — there's nothing to undo. Use it only for an entry added by mistake.",
              name: @member.full_name
            )
          }
          class={[
            "mt-2 text-xs text-hero-grey-500 underline hover:text-red-600",
            Theme.transition(:normal)
          ]}
        >
          {gettext("Delete entry")}
        </button>
      </div>
    </div>
    """
  end

  @doc """
  A team member whose employment has ended.

  Deliberately not the active card greyed out: the only action is bringing them
  back. Editing, resending an invitation or deleting all belong to someone who
  currently works here, so reinstate first and act after.
  """
  attr :member, :map, required: true

  def former_member_card(assigns) do
    ~H"""
    <div class={[
      "flex items-center justify-between gap-3 bg-white border border-hero-grey-200 px-4 py-3",
      Theme.rounded(:xl)
    ]}>
      <div class="min-w-0">
        <p class="font-medium text-hero-charcoal truncate">{@member.full_name}</p>
        <p :if={@member.role} class="text-xs text-hero-grey-500 truncate">{@member.role}</p>
      </div>
      <button
        type="button"
        id={"reactivate-member-#{@member.id}"}
        phx-click="reactivate_member"
        phx-value-id={@member.id}
        class={[
          "shrink-0 px-3 py-2 border border-hero-grey-300 bg-white",
          "hover:bg-hero-grey-50 text-hero-charcoal text-sm font-medium",
          Theme.rounded(:lg),
          Theme.transition(:normal)
        ]}
      >
        {gettext("Add back to team")}
      </button>
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
  The sentence naming why removing a capacity cap is consequential.

  Lives here, not in the LiveView, because both the inline warning and the flash that
  reports a refused removal must say the same thing — and the wording is rendered in
  the reader's locale either way.
  """
  @spec cap_removal_message({:cap_removal, pos_integer()} | pos_integer()) :: String.t()
  def cap_removal_message({:cap_removal, active}), do: cap_removal_message(active)

  def cap_removal_message(active) when is_integer(active) do
    ngettext(
      "%{count} child is already enrolled. Confirm you want this program to have no capacity limit.",
      "%{count} children are already enrolled. Confirm you want this program to have no capacity limit.",
      active
    )
  end

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

  attr :cap_removal_assessment, :any,
    default: :ok,
    doc: "`:ok`, or `{:cap_removal, active_count}` from Enrollment.assess_capacity_change/2"

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

        <div class="space-y-3">
          <p class="text-sm font-semibold text-hero-charcoal">{gettext("Schedule (optional)")}</p>

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

          <div
            :if={@cap_removal_assessment != :ok}
            id="cap-removal-warning"
            class={[
              "flex items-start gap-3 p-4 border border-amber-200 bg-amber-50 text-amber-800",
              Theme.rounded(:lg),
              Theme.typography(:body_small)
            ]}
          >
            <.icon name="hero-exclamation-triangle-mini" class="w-5 h-5 shrink-0 mt-0.5" />
            <div class="flex-1">
              <p class="font-medium">{cap_removal_message(@cap_removal_assessment)}</p>
              <p class="mt-1">
                {gettext("Anyone will be able to book a place until you set a new maximum.")}
              </p>
              <.input
                field={@enrollment_form[:acknowledge_cap_removal]}
                type="checkbox"
                label={gettext("I understand this program will have no capacity limit.")}
                required
              />
            </div>
          </div>
        </div>

        <div class="space-y-4">
          <div>
            <p class="text-sm font-semibold text-hero-charcoal">
              {gettext("Participant Restrictions (optional)")}
            </p>
            <p class="text-xs text-hero-grey-500">
              {gettext("Define age, gender, or grade restrictions for eligible participants.")}
            </p>
          </div>

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

        <%!-- Lead only. Everyone else on the program is managed from the
              staffing panel, which writes the same program_staff_assignments rows. --%>
        <.input
          field={@form[:instructor_id]}
          type="select"
          label={gettext("Lead Instructor")}
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
          <%!-- Each control needs its own <form>: LiveView refuses a phx-change on a
                bare input ("form events require the input to be inside a form"), so
                until this wrapper existed neither search nor the staff filter fired
                in a browser at all — only in tests, where render_change/2 posts to
                the server directly and never sees the client-side check. --%>
          <div class="flex flex-col sm:flex-row gap-2">
            <form phx-change="search_programs" id="programs-search-form" class="relative">
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
                phx-debounce="300"
              />
            </form>
            <form phx-change="filter_by_staff" id="programs-staff-filter-form" class="relative">
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
              >
                <option
                  :for={option <- @staff_options}
                  value={option.value}
                  selected={option.value == @selected_staff}
                >
                  {option.label}
                </option>
              </select>
            </form>
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
                <%!-- Three distinct states: led, staffed-but-leaderless, empty. Collapsing
                      the middle one into "Unassigned" is what #1310 was about. --%>
                <div
                  :if={program.assigned_staff.lead}
                  id={"program-staff-lead-#{program.id}"}
                  class="flex items-center gap-2"
                >
                  <div class={[
                    "w-8 h-8 shrink-0 flex items-center justify-center text-white text-xs font-medium",
                    Theme.rounded(:full),
                    Theme.gradient(:primary)
                  ]}>
                    {program.assigned_staff.lead.initials}
                  </div>
                  <span class="text-sm text-hero-charcoal">{program.assigned_staff.lead.name}</span>
                  <span
                    :if={program.assigned_staff.others_count > 0}
                    class="text-sm text-hero-grey-500 whitespace-nowrap"
                  >
                    +{program.assigned_staff.others_count}
                  </span>
                </div>
                <span
                  :if={!program.assigned_staff.lead and program.assigned_staff.count > 0}
                  id={"program-staff-leaderless-#{program.id}"}
                  class="text-sm text-hero-grey-500"
                >
                  {ngettext(
                    "%{count} staff member · no lead",
                    "%{count} staff · no lead",
                    program.assigned_staff.count
                  )}
                </span>
                <span
                  :if={program.assigned_staff.count == 0}
                  id={"program-staff-empty-#{program.id}"}
                  class="text-sm text-hero-grey-400 italic"
                >
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
                    id={"manage-staffing-#{program.id}"}
                    icon="hero-identification-mini"
                    title={gettext("Manage Staffing")}
                    phx-click="manage_staffing"
                    phx-value-id={program.id}
                  />
                  <.action_button
                    id={"manage-waivers-#{program.id}"}
                    icon="hero-shield-check-mini"
                    title={gettext("Manage Waivers")}
                    phx-click="manage_waivers"
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
  attr :intent, :atom, default: :neutral, values: [:neutral, :promote, :destructive]
  attr :rest, :global, include: ~w(id phx-click phx-value-id phx-value-program-id)

  defp action_button(assigns) do
    ~H"""
    <button
      type="button"
      title={@title}
      aria-label={@title}
      disabled={@disabled}
      class={
        [
          # 44px, not the 36px a bare `p-2` glyph gives: on a phone these are the
          # panel's primary controls and there is no hover to discover them by.
          "inline-flex min-h-11 min-w-11 items-center justify-center border",
          Theme.rounded(:md),
          Theme.transition(:fast),
          if(@disabled,
            do: "border-hero-grey-100 bg-hero-grey-50 text-hero-grey-300 cursor-not-allowed",
            else: action_button_intent(@intent)
          )
        ]
      }
      {@rest}
    >
      <.icon name={@icon} class="w-5 h-5" />
    </button>
    """
  end

  # A resting surface — border plus fill — so the control reads as pressable before
  # anyone touches it, then a press state and a focus ring. The hover tint splits by
  # intent because two adjacent icon-only buttons that highlight identically give no
  # clue which one is the one you cannot undo.
  @action_button_base "bg-white text-hero-grey-700 border-hero-grey-200 active:scale-95 " <>
                        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-1"

  defp action_button_intent(:destructive),
    do: @action_button_base <> " hover:border-red-200 hover:bg-red-50 hover:text-red-600 focus-visible:ring-red-400"

  defp action_button_intent(:promote),
    do:
      @action_button_base <>
        " hover:border-hero-yellow-700 hover:bg-hero-yellow-100 hover:text-hero-grey-900 focus-visible:ring-hero-yellow-700"

  defp action_button_intent(:neutral),
    do:
      @action_button_base <>
        " hover:border-hero-grey-300 hover:bg-hero-grey-50 hover:text-hero-grey-900 focus-visible:ring-hero-grey-400"

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
          <div class="flex items-center justify-between p-4 border-b border-hero-grey-200">
            <h3 class="text-lg font-semibold text-hero-charcoal">
              {gettext("Roster: %{name}", name: @program_name)}
            </h3>
            <div class="flex items-center gap-1">
              <%!-- Disabled with tooltip when roster is empty; navigates to BroadcastLive with program context when populated --%>
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
  staff, attendance count, and status.

  "Assigned staff" is the session's *effective* staffing: its own override roster
  where the provider set one, the program roster otherwise (#782).

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

  @doc """
  Renders the waivers panel for one program: the legal forms parents sign at enrollment.

  Editing publishes a *new* version rather than rewriting the current one, and archiving
  retires a form without deleting it — both because a signature is only evidence while the
  wording it was given stays reproducible.

  ## Example

      <.waivers_modal :if={@waivers_modal} modal={@waivers_modal} />
  """
  attr :modal, :map, required: true

  def waivers_modal(assigns) do
    ~H"""
    <div
      id="program-waivers-modal"
      role="dialog"
      aria-modal="true"
      aria-labelledby="program-waivers-modal-title"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
      phx-window-keydown="close_waivers"
      phx-key="escape"
    >
      <div
        class="bg-white rounded-lg shadow-xl w-full max-w-2xl max-h-[85vh] overflow-hidden flex flex-col"
        phx-click-away="close_waivers"
      >
        <div class="flex items-center justify-between px-4 py-4 sm:px-6 border-b border-hero-grey-200">
          <h2 id="program-waivers-modal-title" class={Theme.typography(:section_title)}>
            {gettext("Waivers — %{title}", title: @modal.program_name)}
          </h2>
          <button type="button" phx-click="close_waivers" aria-label={gettext("Close")}>
            <.icon name="hero-x-mark" class="w-5 h-5" />
          </button>
        </div>

        <div class="flex-1 overflow-y-auto px-4 py-4 sm:px-6 space-y-6">
          <p :if={@modal.waivers == []} id="waivers-empty" class="text-sm text-hero-grey-500">
            {gettext("No waivers yet. Parents enrol without signing anything.")}
          </p>

          <ul :if={@modal.waivers != []} id="waiver-list" class="divide-y divide-hero-grey-100">
            <li
              :for={entry <- @modal.waivers}
              id={"waiver-#{entry.waiver.id}"}
              class="flex items-start gap-3 py-3"
            >
              <div class="min-w-0 flex-1">
                <%!-- The badge sits outside the truncating title, or a long title swallows it
                      on a narrow viewport — losing the one word that says this one blocks. --%>
                <div class="flex items-center gap-2">
                  <p class="truncate font-medium text-hero-charcoal">{entry.waiver.title}</p>
                  <span
                    :if={entry.waiver.required}
                    class="shrink-0 inline-block px-2 py-0.5 text-xs font-semibold bg-hero-yellow-500 text-hero-grey-900 rounded-full"
                  >
                    {gettext("Required")}
                  </span>
                </div>
                <p class="text-sm text-hero-grey-500">
                  {gettext("Version %{number}", number: entry.version.version)}
                </p>
              </div>

              <div class="flex shrink-0 items-center gap-1">
                <.action_button
                  id={"edit-waiver-#{entry.waiver.id}"}
                  icon="hero-pencil-square-mini"
                  title={gettext("Revise text")}
                  phx-click="edit_waiver"
                  phx-value-id={entry.waiver.id}
                />
                <%!-- Retiring cannot be undone from the UI, so it gets the same confirm as
                      the other one-click destructive actions in this file. --%>
                <.action_button
                  id={"archive-waiver-#{entry.waiver.id}"}
                  icon="hero-archive-box-mini"
                  title={gettext("Retire this waiver")}
                  phx-click="archive_waiver"
                  phx-value-id={entry.waiver.id}
                  data-confirm={
                    gettext(
                      "Retire \"%{title}\"? Parents will no longer be asked to sign it. Signatures already collected are kept.",
                      title: entry.waiver.title
                    )
                  }
                />
              </div>
            </li>
          </ul>

          <.form for={@modal.form} id="waiver-form" phx-submit="save_waiver" class="space-y-4">
            <h3 class={[Theme.typography(:card_title), "text-hero-charcoal"]}>
              {if @modal.editing_id,
                do: gettext("Publish a new version"),
                else: gettext("Add a waiver")}
            </h3>

            <.input
              :if={!@modal.editing_id}
              field={@modal.form[:title]}
              type="text"
              label={gettext("Title")}
            />

            <.input
              field={@modal.form[:body]}
              type="textarea"
              rows="8"
              label={gettext("Legal text")}
            />

            <.input
              :if={!@modal.editing_id}
              field={@modal.form[:required]}
              type="checkbox"
              label={gettext("Parents must sign this before enrolling")}
            />

            <p :if={@modal.editing_id} class="text-xs text-hero-grey-500">
              {gettext(
                "Publishing keeps every earlier version on record; signatures already given stay bound to the wording they were shown."
              )}
            </p>

            <div class="flex gap-2">
              <.kh_button type="submit" id="save-waiver">
                {if @modal.editing_id, do: gettext("Publish version"), else: gettext("Add waiver")}
              </.kh_button>
              <.kh_button
                :if={@modal.editing_id}
                type="button"
                variant={:secondary}
                id="cancel-waiver-edit"
                phx-click="cancel_waiver_edit"
              >
                {gettext("Cancel")}
              </.kh_button>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders the staffing panel for one program: who is on it, who leads it, and the
  controls to add, promote and remove.

  Named "staffing" rather than "team" because `/provider/team` is already the
  provider's staff directory — this is the per-program subset of it.

  ## Example

      <.staffing_modal :if={@staffing_modal} modal={@staffing_modal} />
  """
  attr :modal, :map, required: true

  def staffing_modal(assigns) do
    ~H"""
    <div
      id="program-staffing-modal"
      role="dialog"
      aria-modal="true"
      aria-labelledby="program-staffing-modal-title"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
      phx-window-keydown="close_staffing"
      phx-key="escape"
    >
      <div
        class="bg-white rounded-lg shadow-xl w-full max-w-lg max-h-[85vh] overflow-hidden flex flex-col"
        phx-click-away="close_staffing"
      >
        <div class="flex items-center justify-between px-4 py-4 sm:px-6 border-b border-hero-grey-200">
          <h2 id="program-staffing-modal-title" class={Theme.typography(:section_title)}>
            {gettext("Staffing — %{title}", title: @modal.program_name)}
          </h2>
          <button type="button" phx-click="close_staffing" aria-label={gettext("Close")}>
            <.icon name="hero-x-mark" class="w-5 h-5" />
          </button>
        </div>

        <div class="flex-1 overflow-y-auto px-4 py-4 sm:px-6">
          <ul :if={@modal.members != []} id="staffing-members" class="divide-y divide-hero-grey-100">
            <li
              :for={member <- @modal.members}
              id={"staffing-member-#{member.id}"}
              class="flex items-center gap-3 py-3"
            >
              <.staff_avatar member={member} />

              <div class="min-w-0 flex-1">
                <p class="truncate font-medium text-hero-charcoal">
                  {member.full_name}
                  <span
                    :if={member.lead?}
                    id={"staffing-lead-badge-#{member.id}"}
                    class="ml-1 inline-block px-2 py-0.5 text-xs font-semibold bg-hero-yellow-500 text-hero-grey-900 rounded-full align-middle"
                  >
                    {gettext("Lead")}
                  </span>
                </p>
                <p :if={member.role} class="truncate text-sm text-hero-grey-500">{member.role}</p>
              </div>

              <div class="flex shrink-0 items-center gap-1">
                <.action_button
                  :if={!member.lead?}
                  id={"promote-staff-#{member.id}"}
                  icon="hero-star-mini"
                  intent={:promote}
                  title={gettext("Make lead instructor")}
                  phx-click="promote_to_lead"
                  phx-value-staff-id={member.id}
                />
                <%!-- Disabled, not hidden: the reason the lead cannot be removed
                      is worth showing. The context refuses regardless. --%>
                <.action_button
                  id={"remove-staff-#{member.id}"}
                  icon="hero-user-minus-mini"
                  intent={:destructive}
                  title={
                    if(member.lead?,
                      do: gettext("Reassign the lead before removing them"),
                      else: gettext("Remove from program")
                    )
                  }
                  disabled={member.lead?}
                  phx-click="remove_staff_member"
                  phx-value-staff-id={member.id}
                />
              </div>
            </li>
          </ul>

          <p
            :if={@modal.members == []}
            id="staffing-empty"
            class="py-6 text-center text-hero-grey-500"
          >
            {gettext("Nobody is on this program yet.")}
          </p>

          <div class="mt-4 border-t border-hero-grey-200 pt-4">
            <form
              phx-submit="assign_staff_member"
              id="staffing-add-form"
              class="flex flex-col gap-2 sm:flex-row"
            >
              <select
                id="staffing-add-select"
                name="staff-id"
                disabled={@modal.assignable_options == []}
                class={[
                  "flex-1 border border-hero-grey-300 px-3 py-2 text-hero-charcoal disabled:bg-hero-grey-50",
                  Theme.rounded(:lg)
                ]}
              >
                <option value="">{gettext("Select a staff member…")}</option>
                <option :for={{label, value} <- @modal.assignable_options} value={value}>
                  {label}
                </option>
              </select>
              <button
                type="submit"
                id="staffing-add-btn"
                disabled={@modal.assignable_options == []}
                class={[
                  "flex items-center justify-center gap-2 px-4 py-2 font-semibold",
                  "bg-hero-yellow hover:bg-hero-yellow-dark text-hero-charcoal",
                  "disabled:bg-hero-grey-100 disabled:text-hero-grey-400",
                  Theme.rounded(:lg),
                  Theme.transition(:normal)
                ]}
              >
                <.icon name="hero-plus-mini" class="w-5 h-5" />
                {gettext("Add")}
              </button>
            </form>

            <p class="mt-2 text-xs text-hero-grey-400">
              {gettext("Staff you add can read and reply to this program's parent conversations.")}
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders the staffing panel for one *session*: who is working it, who leads it,
  and the controls to add, promote, remove and revert (#782).

  The session sibling of `staffing_modal/1`, and deliberately a separate component
  rather than a mode on it: this one has to say **where its roster came from**. A
  session with no overrides shows the program's roster and offers to override it; a
  session that has been overridden shows its own people and offers to revert. That
  distinction is the whole feature, and folding it into a flag would bury it.

  ## Example

      <.session_staffing_modal :if={@session_staffing_modal} modal={@session_staffing_modal} />
  """
  attr :modal, :map, required: true

  def session_staffing_modal(assigns) do
    ~H"""
    <div
      id="session-staffing-modal"
      role="dialog"
      aria-modal="true"
      aria-labelledby="session-staffing-modal-title"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
      phx-window-keydown="close_session_staffing"
      phx-key="escape"
    >
      <div
        class="bg-white rounded-lg shadow-xl w-full max-w-lg max-h-[85vh] overflow-hidden flex flex-col"
        phx-click-away="close_session_staffing"
      >
        <div class="flex items-start justify-between gap-3 px-4 py-4 sm:px-6 border-b border-hero-grey-200">
          <div class="min-w-0">
            <h2 id="session-staffing-modal-title" class={Theme.typography(:section_title)}>
              {gettext("Staffing — %{date}", date: @modal.session_label)}
            </h2>
            <p class="mt-1 truncate text-sm text-hero-grey-500">{@modal.program_title}</p>
          </div>
          <.action_button
            id="session-staffing-close"
            icon="hero-x-mark"
            title={gettext("Close")}
            phx-click="close_session_staffing"
          />
        </div>

        <div class="flex-1 overflow-y-auto px-4 py-4 sm:px-6">
          <%!-- Where this roster came from is the panel's headline fact, not a footnote:
                everything below reads differently depending on it. --%>
          <div
            id="session-staffing-source"
            class={[
              "mb-4 flex items-start gap-2 px-3 py-2 text-sm",
              Theme.rounded(:lg),
              if(@modal.overridden?,
                do: "bg-hero-yellow-100 text-hero-grey-900",
                else: "bg-hero-grey-50 text-hero-grey-600"
              )
            ]}
          >
            <.icon
              name={if(@modal.overridden?, do: "hero-user-plus-mini", else: "hero-users-mini")}
              class="w-5 h-5 shrink-0"
            />
            <span>
              <%= if @modal.overridden? do %>
                {gettext("Staffed just for this session. Changes here do not touch the program.")}
              <% else %>
                {gettext(
                  "Using the program's usual team. The first change here copies them onto this session, so later program changes stop reaching it."
                )}
              <% end %>
            </span>
          </div>

          <ul
            :if={@modal.members != []}
            id="session-staffing-members"
            class="divide-y divide-hero-grey-100"
          >
            <li
              :for={member <- @modal.members}
              id={"session-staffing-member-#{member.id}"}
              class="flex items-center gap-3 py-3"
            >
              <.staff_avatar member={member} />

              <div class="min-w-0 flex-1">
                <p class="truncate font-medium text-hero-grey-900">
                  {member.full_name}
                  <span
                    :if={member.lead?}
                    id={"session-staffing-lead-badge-#{member.id}"}
                    class="ml-1 inline-block px-2 py-0.5 text-xs font-semibold bg-hero-yellow-500 text-hero-grey-900 rounded-full align-middle"
                  >
                    {gettext("Lead")}
                  </span>
                </p>
                <p :if={member.role} class="truncate text-sm text-hero-grey-500">{member.role}</p>
              </div>

              <%!-- Offered whether or not the session already has its own roster: the
                    first change materializes the program's team onto this session
                    rather than replacing it, so acting here no longer discards anyone. --%>
              <div class="flex shrink-0 items-center gap-1">
                <.action_button
                  :if={!member.lead?}
                  id={"promote-session-staff-#{member.id}"}
                  icon="hero-star-mini"
                  intent={:promote}
                  title={gettext("Make lead instructor for this session")}
                  phx-click="promote_session_lead"
                  phx-value-staff-id={member.id}
                />
                <.action_button
                  id={"remove-session-staff-#{member.id}"}
                  icon="hero-user-minus-mini"
                  intent={:destructive}
                  title={session_removal_title(member, @modal.members)}
                  disabled={member.lead? or length(@modal.members) == 1}
                  phx-click="remove_session_staff"
                  phx-value-staff-id={member.id}
                />
              </div>
            </li>
          </ul>

          <p
            :if={@modal.members == []}
            id="session-staffing-empty"
            class="py-6 text-center text-hero-grey-500"
          >
            {gettext("Nobody is working this session yet.")}
          </p>

          <div class="mt-4 border-t border-hero-grey-200 pt-4">
            <.form
              for={@modal.add_form}
              phx-submit="assign_session_staff"
              id="session-staffing-add-form"
              class="flex flex-col items-end gap-2 sm:flex-row"
            >
              <%!-- A tracked form input rather than a bare <select>: the option list
                    changes whenever the roster does, and an untracked select loses the
                    provider's pick the moment a re-render rebuilds its options. --%>
              <div class="w-full flex-1">
                <.input
                  field={@modal.add_form[:staff_id]}
                  type="select"
                  id="session-staffing-add-select"
                  prompt={gettext("Select a staff member…")}
                  options={@modal.assignable_options}
                  disabled={@modal.assignable_options == []}
                />
              </div>
              <button
                type="submit"
                id="session-staffing-add-btn"
                disabled={@modal.assignable_options == []}
                class={[
                  "flex min-h-11 w-full items-center justify-center gap-2 px-4 py-2 font-semibold sm:w-auto",
                  "bg-hero-yellow-500 hover:bg-hero-yellow-600 text-hero-grey-900",
                  "active:scale-95 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-hero-yellow-700",
                  "disabled:bg-hero-grey-100 disabled:text-hero-grey-400 disabled:active:scale-100",
                  Theme.rounded(:md),
                  Theme.transition(:fast)
                ]}
              >
                <.icon name="hero-plus-mini" class="w-5 h-5" />
                {gettext("Add")}
              </button>
            </.form>

            <p
              :if={@modal.assignable_options == []}
              id="session-staffing-nobody-addable"
              class="mt-2 text-sm text-hero-grey-500"
            >
              {gettext("Everyone on your team is already working this session.")}
            </p>

            <button
              :if={@modal.overridden?}
              type="button"
              id="session-staffing-revert-btn"
              phx-click="revert_session_staffing"
              class={[
                "mt-3 flex min-h-11 w-full items-center justify-center gap-2 px-4 py-2",
                "border border-hero-grey-300 bg-white text-sm font-medium text-hero-grey-700",
                "hover:border-hero-grey-400 hover:bg-hero-grey-50 hover:text-hero-grey-900",
                "active:scale-95 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-hero-grey-400",
                Theme.rounded(:md),
                Theme.transition(:fast)
              ]}
            >
              <.icon name="hero-arrow-uturn-left-mini" class="w-5 h-5" />
              {gettext("Go back to the program's usual team")}
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Disabled rather than hidden, so the tooltip can say *why* — both refusals come
  # from the context (`:cannot_unassign_lead`, `:cannot_empty_session`), and a
  # control that silently vanishes teaches the provider nothing about the rule.
  defp session_removal_title(%{lead?: true}, _members), do: gettext("Reassign the lead before removing them")

  defp session_removal_title(_member, [_only]),
    do: gettext("A session needs someone — use “Go back to the program's usual team” instead")

  defp session_removal_title(_member, _members), do: gettext("Remove from this session")

  attr :member, :map, required: true

  defp staff_avatar(assigns) do
    ~H"""
    <img
      :if={@member.headshot_url}
      src={@member.headshot_url}
      alt=""
      class="w-9 h-9 shrink-0 rounded-full object-cover"
    />
    <div
      :if={!@member.headshot_url}
      class={[
        "w-9 h-9 shrink-0 rounded-full flex items-center justify-center",
        "text-xs font-semibold text-hero-charcoal",
        Theme.gradient(:primary)
      ]}
      aria-hidden="true"
    >
      {@member.initials}
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
            {gettext("Waivers")}
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
          <td class="px-3 py-3">
            <%!-- A dash rather than "Signed" when the program requires nothing: a provider
                  scanning for who still owes them a form should not see a green tick that
                  means "there was never anything to sign". --%>
            <span id={"waiver-status-#{entry.enrollment_id}"} data-status={entry.waiver_status}>
              <span :if={entry.waiver_status == :not_required} class="text-sm text-hero-grey-400">
                —
              </span>
              <.status_pill
                :if={entry.waiver_status != :not_required}
                color={if entry.waiver_status == :signed, do: "success", else: "warning"}
              >
                {if entry.waiver_status == :signed, do: gettext("Signed"), else: gettext("Unsigned")}
              </.status_pill>
            </span>
          </td>
          <td class="px-3 py-3 text-sm text-hero-grey-500">
            {format_enrollment_date(entry.enrolled_at)}
          </td>
          <td class="px-3 py-3 text-right">
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

      <div :if={@invites == []} id="invites-empty" class="text-center py-8">
        <.icon name="hero-envelope" class="w-12 h-12 mx-auto text-hero-grey-300 mb-3" />
        <p class="text-hero-grey-500">
          {gettext("No invites yet. Upload a CSV to invite families.")}
        </p>
      </div>

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
                <%!-- Written by three places and shown by none until #1221: a red pill with no
                      reason tells a provider that something is wrong but not what to do about it. --%>
                <p
                  :if={invite.status == :failed && failure_message(invite)}
                  id={"invite-error-#{invite.id}"}
                  class="mt-1 text-xs text-hero-grey-500 break-words"
                >
                  {failure_message(invite)}
                </p>
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

  # Invite lifecycle differs from enrollment lifecycle (pending → invite_sent → registered → enrolled)
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

  # Row-level failures: list of %{row, category, errors} maps from ImportEnrollmentCsv
  defp format_import_errors(failures) when is_list(failures) do
    Enum.map(failures, fn %{row: row, category: category, errors: errors} ->
      row_label = if row, do: gettext("Row %{row}", row: row), else: gettext("Row —")
      category_label = category |> to_string() |> String.capitalize()
      error_detail = format_failure_errors(errors)
      "#{row_label} [#{category_label}]: #{error_detail}"
    end)
  end

  # Whole-file parse failure: %{parse_errors: [{row, msg}]}
  defp format_import_errors(%{parse_errors: errs}) when is_list(errs) do
    Enum.map(errs, fn {_row, msg} -> msg end)
  end

  defp format_import_errors(_), do: [gettext("An unexpected error occurred during import.")]

  defp format_failure_errors(errors) when is_binary(errors), do: errors

  defp format_failure_errors(errors) when is_list(errors) do
    Enum.map_join(errors, ", ", fn {field, msg} -> "#{humanize_field(field)}: #{msg}" end)
  end

  # The sentence a provider reads under a failed invite's status pill.
  #
  # `Enrollment` stores the *cause*, not the copy: every writer is a background process,
  # so a sentence built there would be frozen in that process's locale (#1340). The
  # wording lives here, where the reader's locale is the one in scope.
  defp failure_message(%{failure_code: nil, error_details: legacy}), do: legacy

  defp failure_message(%{failure_code: :no_token}),
    do: dgettext("enrollment", "Invite link could not be generated (no token). Please resend.")

  defp failure_message(%{failure_code: :program_full}),
    do: dgettext("enrollment", "The program is full, so this child could not be enrolled.")

  defp failure_message(%{failure_code: :invalid_date, failure_context: %{"value" => value}}) do
    dgettext(
      "enrollment",
      "Date of birth \"%{value}\" is not a valid date. Please correct it and resend.",
      value: value
    )
  end

  defp failure_message(%{failure_code: :delivery_failed}),
    do: dgettext("enrollment", "The invitation email could not be delivered. Please check the address and resend.")

  defp failure_message(%{failure_code: :exhausted}),
    do: dgettext("enrollment", "This invite could not be completed and no retries remain. Please resend.")

  defp failure_message(%{failure_code: :invalid_details, failure_context: %{"fields" => fields}})
       when is_list(fields) do
    Enum.map_join(fields, "; ", &changeset_field_message/1)
  end

  # Also the landing place for a code whose context did not survive — naming no detail
  # beats raising on the render path.
  defp failure_message(%{}), do: dgettext("enrollment", "This invite could not be completed. Please resend.")

  defp changeset_field_message(%{"field" => field, "msg" => msg} = error) do
    bindings = Map.get(error, "bindings", %{})

    "#{humanize_field(field)} #{translate_changeset_message(msg, bindings)}"
  end

  # Translate first, interpolate second: the German msgstr carries the placeholders too.
  # The msgid is a runtime value, so this is `Gettext.d*gettext/4` the function rather
  # than the macro — the "errors" catalog already holds Ecto's own messages.
  #
  # Gettext gets the bindings it can resolve itself, or it logs a missing-binding error
  # on every render of the row; `interpolate/2` then covers any key outside that set.
  defp translate_changeset_message(msg, bindings) do
    msg
    |> translate_errors_domain(bindings)
    |> ChangesetErrors.interpolate(bindings)
  end

  defp translate_errors_domain(msg, %{"count" => count} = bindings) when is_integer(count) do
    Gettext.dngettext(
      KlassHeroWeb.Gettext,
      "errors",
      msg,
      msg,
      count,
      ChangesetErrors.gettext_bindings(bindings)
    )
  end

  defp translate_errors_domain(msg, bindings) do
    Gettext.dgettext(KlassHeroWeb.Gettext, "errors", msg, ChangesetErrors.gettext_bindings(bindings))
  end

  # Field names arrive as atoms from a live import failure and as strings from a stored
  # invite failure (#1340) — one vocabulary serves both, keyed on the string.
  defp humanize_field(field) when is_atom(field), do: field |> Atom.to_string() |> humanize_field()

  # dgettext must run at call-time (not module-attribute time) for i18n to work
  defp humanize_field("child_first_name"), do: dgettext("enrollment", "Child first name")
  defp humanize_field("child_last_name"), do: dgettext("enrollment", "Child last name")
  defp humanize_field("child_date_of_birth"), do: dgettext("enrollment", "Date of birth")
  defp humanize_field("guardian_email"), do: dgettext("enrollment", "Guardian email")
  defp humanize_field("guardian_first_name"), do: dgettext("enrollment", "Guardian first name")
  defp humanize_field("guardian_last_name"), do: dgettext("enrollment", "Guardian last name")
  defp humanize_field("guardian2_email"), do: dgettext("enrollment", "Second guardian email")

  defp humanize_field("guardian2_first_name"), do: dgettext("enrollment", "Second guardian first name")

  defp humanize_field("guardian2_last_name"), do: dgettext("enrollment", "Second guardian last name")

  defp humanize_field("program_name"), do: dgettext("enrollment", "Program")
  defp humanize_field("school_grade"), do: dgettext("enrollment", "Grade")
  defp humanize_field("school_name"), do: dgettext("enrollment", "School")

  # A claim failure names the Child's own fields, which the CSV spells differently.
  defp humanize_field("first_name"), do: dgettext("enrollment", "Child first name")
  defp humanize_field("last_name"), do: dgettext("enrollment", "Child last name")
  defp humanize_field("date_of_birth"), do: dgettext("enrollment", "Date of birth")

  defp humanize_field(field) when is_binary(field) do
    field |> String.replace("_", " ") |> String.capitalize()
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
  attr :video_upload?, :boolean, default: false, doc: "Whether the track includes a video-screening step"

  def verification_documents_panel(assigns) do
    ~H"""
    <div class={["bg-white p-6 shadow-sm border border-hero-grey-200", Theme.rounded(:xl)]}>
      <h2 class="text-lg font-semibold text-hero-charcoal mb-4">
        {gettext("Verification Documents")}
      </h2>
      <p class="text-sm text-hero-grey-500 mb-6">
        {gettext("Upload documents to verify your business. Documents are reviewed by our team.")}
      </p>

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
                selected={to_string(type) == @doc_type}
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

      <div :if={@video_upload?} class="border-t border-hero-grey-200 pt-6 mt-6">
        <h3 class="text-sm font-semibold text-hero-charcoal mb-1">
          {gettext("Video Screening")}
        </h3>
        <p class="text-sm text-hero-grey-500 mb-3">
          {gettext(
            "Record a short video introducing yourself. Our team reviews it to assess communication skills and alignment with our values."
          )}
        </p>

        <form
          id="video-upload-form"
          phx-submit="upload_verification_video"
          phx-change="validate_upload"
          class="space-y-4"
        >
          <div>
            <.live_file_input upload={@uploads.verification_video} class="hidden" />
            <label
              for={@uploads.verification_video.ref}
              class={[
                "inline-flex items-center gap-2 px-4 py-2 border border-hero-grey-300",
                "bg-white hover:bg-hero-grey-50 text-hero-charcoal text-sm font-medium cursor-pointer",
                Theme.rounded(:lg),
                Theme.transition(:normal)
              ]}
            >
              <.icon name="hero-video-camera-mini" class="w-4 h-4" />
              {gettext("Select Video")}
            </label>
            <p class="text-xs text-hero-grey-400 mt-2">
              {gettext("MP4, MOV or WEBM. Max 100MB.")}
            </p>
            <div
              :for={entry <- @uploads.verification_video.entries}
              class={[
                "flex items-center gap-3 mt-3 px-3 py-2 border border-hero-grey-200",
                "bg-hero-grey-50",
                Theme.rounded(:lg)
              ]}
            >
              <.icon name="hero-film-mini" class="w-5 h-5 text-hero-grey-500 shrink-0" />
              <span class="text-sm text-hero-charcoal truncate flex-1">{entry.client_name}</span>
              <button
                type="button"
                phx-click="cancel_upload"
                phx-value-ref={entry.ref}
                phx-value-upload="verification_video"
                class="text-xs text-red-500 hover:text-red-700 shrink-0"
              >
                {gettext("Remove")}
              </button>
              <div
                :for={err <- upload_errors(@uploads.verification_video, entry)}
                class="text-xs text-red-500"
              >
                {upload_error_to_string(err)}
              </div>
            </div>
          </div>

          <button
            type="submit"
            id="upload-video-btn"
            disabled={@uploads.verification_video.entries == []}
            class={[
              "flex items-center gap-2 px-4 py-2 border border-hero-grey-300",
              "bg-white hover:bg-hero-grey-50 text-hero-charcoal text-sm font-medium",
              "disabled:opacity-50 disabled:cursor-not-allowed",
              Theme.rounded(:lg),
              Theme.transition(:normal)
            ]}
          >
            <.icon name="hero-arrow-up-tray-mini" class="w-4 h-4" />
            {gettext("Upload Video")}
          </button>
        </form>
      </div>
    </div>
    """
  end

  @doc """
  Renders a signed-agreement vetting step (the Community Standards Agreement B4, or the Staff
  Compliance Declaration B5) — the shared card chrome: header, the already-signed confirmation
  (when `@satisfied?`), or the else branch with an optional stale-version notice, the scrollable
  legal body, an optional attachment (e.g. a PDF link), the business signer line, and the
  checkbox + submit form. The per-kind legal text, copy, and DOM ids come from the caller; the two
  panels below are thin wrappers over this one skeleton.
  """
  attr :record, :any, required: true, doc: "The provider's latest SignedAgreement of this kind, or nil"
  attr :satisfied?, :boolean, required: true, doc: "Whether the latest record meets the current version"
  attr :form, :any, required: true, doc: "The checkbox form"
  attr :signer_name, :string, default: nil, doc: "Business responsible-person signer; nil for an individual"
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :signed_label, :string, required: true, doc: "Headline shown once signed"
  attr :checkbox_label, :string, required: true
  attr :submit_label, :string, required: true
  attr :form_id, :string, required: true
  attr :signer_id, :string, required: true
  attr :submit_btn_id, :string, required: true
  attr :body_id, :string, required: true
  attr :submit_event, :string, required: true

  slot :updated_notice, doc: "Amber re-sign copy, shown only when a stale `@record` exists"
  slot :notice, doc: "Optional banner rendered before the body (e.g. a provisional-text warning)"
  slot :body, required: true, doc: "The legal text body"
  slot :attachment, doc: "Optional block after the body (e.g. a PDF download link)"

  def signed_agreement_panel(assigns) do
    ~H"""
    <div class={["bg-white p-6 shadow-sm border border-hero-grey-200", Theme.rounded(:xl)]}>
      <h2 class={[Theme.typography(:card_title), Theme.text_color(:heading), "mb-1"]}>
        {@title}
      </h2>
      <p class={[Theme.typography(:body_small), Theme.text_color(:muted), "mb-4"]}>
        {@description}
      </p>

      <%= if @satisfied? do %>
        <div class={[
          "flex items-start gap-3 p-4 border border-green-200 bg-green-50",
          Theme.rounded(:lg)
        ]}>
          <.icon name="hero-check-circle-mini" class="w-5 h-5 text-green-600 shrink-0 mt-0.5" />
          <div class={[Theme.typography(:body_small), Theme.text_color(:body)]}>
            <p class="font-medium">{@signed_label}</p>
            <p :if={@record} class={[Theme.text_color(:muted), "mt-1"]}>
              {gettext("Signed by %{name} on %{date} (v%{version}).",
                name: @record.signed_by_name,
                date: Calendar.strftime(@record.signed_at, "%d %B %Y"),
                version: @record.version
              )}
            </p>
          </div>
        </div>
      <% else %>
        <div
          :if={@record}
          class={[
            "mb-4 p-3 border border-amber-200 bg-amber-50 text-amber-800",
            Theme.rounded(:lg),
            Theme.typography(:body_small)
          ]}
        >
          {render_slot(@updated_notice)}
        </div>

        {render_slot(@notice)}

        <div
          id={@body_id}
          class={[
            "max-h-80 overflow-y-auto p-4 border border-hero-grey-200 bg-hero-grey-50",
            Theme.rounded(:lg)
          ]}
        >
          {render_slot(@body)}
        </div>

        {render_slot(@attachment)}

        <p
          :if={@signer_name}
          id={@signer_id}
          class={[
            "mt-4 p-3 border border-hero-grey-200 bg-hero-grey-50",
            Theme.rounded(:lg),
            Theme.typography(:body_small),
            Theme.text_color(:body)
          ]}
        >
          {gettext("Signing as %{name} on behalf of the business.", name: @signer_name)}
        </p>

        <.form for={@form} id={@form_id} phx-submit={@submit_event} class="mt-4 space-y-4">
          <.input field={@form[:agree]} type="checkbox" label={@checkbox_label} />
          <button
            type="submit"
            id={@submit_btn_id}
            class={[
              "inline-flex items-center gap-2 px-4 py-2 text-sm font-semibold",
              Theme.rounded(:lg),
              Theme.button_variant(:primary),
              Theme.transition(:normal)
            ]}
          >
            <.icon name="hero-check-mini" class="w-4 h-4" />
            {@submit_label}
          </button>
        </.form>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders the Community Standards Agreement step (B4): a `signed_agreement_panel` with the
  Community Guidelines body and a PDF download link.
  """
  attr :agreement, :any, required: true, doc: "The provider's latest SignedAgreement, or nil"
  attr :satisfied?, :boolean, required: true, doc: "Whether the latest agreement meets the current version"
  attr :version, :string, required: true, doc: "The current guidelines version (drives the PDF link)"
  attr :form, :any, required: true, doc: "The agreement checkbox form"

  attr :signer_name, :string,
    default: nil,
    doc: "For a business, the responsible person who signs on its behalf (B4); nil for an individual"

  def community_agreement_panel(assigns) do
    ~H"""
    <.signed_agreement_panel
      record={@agreement}
      satisfied?={@satisfied?}
      form={@form}
      signer_name={@signer_name}
      title={gettext("Community Standards Agreement")}
      description={gettext("The final step: read and agree to the Klass Hero Community Guidelines.")}
      signed_label={gettext("You have agreed to the Community Guidelines.")}
      checkbox_label={gettext("I have read and agree to the Klass Hero Community Guidelines.")}
      submit_label={gettext("Confirm agreement")}
      form_id="community-agreement-form"
      signer_id="agreement-signer"
      submit_btn_id="submit-agreement-btn"
      body_id="community-guidelines"
      submit_event="submit_community_agreement"
    >
      <:updated_notice>
        {gettext(
          "The Community Guidelines have been updated since you last agreed (v%{old}). Please review and re-agree.",
          old: @agreement.version
        )}
      </:updated_notice>
      <:body>{guidelines_body(assigns)}</:body>
      <:attachment>
        <div class="mt-3">
          <.link
            href={community_guidelines_pdf_path(@version)}
            target="_blank"
            rel="noopener noreferrer"
            class="inline-flex items-center gap-2 text-sm font-medium text-hero-cyan hover:underline"
          >
            <.icon name="hero-arrow-down-tray-mini" class="w-4 h-4" />
            {gettext("Download the agreement (PDF)")}
          </.link>
        </div>
      </:attachment>
    </.signed_agreement_panel>
    """
  end

  @doc """
  Renders the Staff Compliance Declaration step (B5): a `signed_agreement_panel` with the German
  declaration body and a "provisional / pending legal review" notice. No PDF — the declaration is a
  contractual statement, not a downloadable artifact.

  The declaration text is **provisional** pending legal review; the panel says so explicitly.
  """
  attr :attestation, :any, required: true, doc: "The provider's latest staff-attestation SignedAgreement, or nil"
  attr :satisfied?, :boolean, required: true, doc: "Whether the latest attestation meets the current version"
  attr :form, :any, required: true, doc: "The attestation checkbox form"

  attr :signer_name, :string,
    default: nil,
    doc: "The responsible person who attests on the business's behalf (B5); nil if none on record"

  def staff_attestation_panel(assigns) do
    ~H"""
    <.signed_agreement_panel
      record={@attestation}
      satisfied?={@satisfied?}
      form={@form}
      signer_name={@signer_name}
      title={gettext("Staff Compliance Declaration")}
      description={
        gettext(
          "Confirm, on behalf of your business, that all staff are vetted per German child-safety law."
        )
      }
      signed_label={gettext("You have signed the Staff Compliance Declaration.")}
      checkbox_label={
        gettext(
          "I confirm, on behalf of the business, that the above declaration is true and I am authorised to sign it."
        )
      }
      submit_label={gettext("Sign the declaration")}
      form_id="staff-attestation-form"
      signer_id="attestation-signer"
      submit_btn_id="submit-attestation-btn"
      body_id="staff-attestation-declaration"
      submit_event="submit_staff_attestation"
    >
      <:updated_notice>
        {gettext(
          "The Staff Compliance Declaration has been updated since you last signed (v%{old}). Please review and re-sign.",
          old: @attestation.version
        )}
      </:updated_notice>
      <:notice>
        <div class={[
          "mb-4 flex items-start gap-3 p-3 border border-amber-300 bg-amber-50 text-amber-900",
          Theme.rounded(:lg),
          Theme.typography(:body_small)
        ]}>
          <.icon name="hero-exclamation-triangle-mini" class="w-5 h-5 shrink-0 mt-0.5" />
          <span>
            {gettext("Provisional text — pending review by a German-qualified lawyer before go-live.")}
          </span>
        </div>
      </:notice>
      <:body>{attestation_body(assigns)}</:body>
    </.signed_agreement_panel>
    """
  end

  # The Provider Child Safety Compliance Declaration body (PROVISIONAL, v1.0-provisional). Not
  # translated — it is a legal artifact tied to a specific `version`. The clauses below are a
  # working draft of the § 72a SGB VIII / § 278 BGB obligations; the Vertragsstrafe (§ 339 BGB)
  # amount is a placeholder pending legal counsel. Must be replaced with lawyer-approved text (and
  # a bumped version, which auto-forces re-attestation) before go-live.
  defp attestation_body(assigns) do
    ~H"""
    <div class={["space-y-5 leading-relaxed", Theme.typography(:body_small), Theme.text_color(:body)]}>
      <p class="font-medium">
        Provider Child Safety Compliance Declaration — Erklärung zur Einhaltung des Kinderschutzes
      </p>
      <p>
        Der Provider erklärt gegenüber Klass Hero, dass alle Personen, die im Auftrag des Providers
        mit Kindern oder Jugendlichen arbeiten (Betreuer:innen, Kursleiter:innen und sonstiges
        Personal), vor ihrem Einsatz und fortlaufend gemäß § 72a SGB VIII sowie § 30a BZRG durch
        Einsichtnahme in ein gültiges erweitertes Führungszeugnis überprüft wurden.
      </p>

      <.guidelines_section title="1. Prüfpflicht (§ 72a SGB VIII, § 30a BZRG)">
        <.guidelines_bullets items={[
          "Der Provider nimmt vor Aufnahme der Tätigkeit Einsicht in ein erweitertes Führungszeugnis jeder mit Minderjährigen betrauten Person.",
          "Die Einsichtnahme wird in regelmäßigen Abständen wiederholt.",
          "Klass Hero erhält oder speichert zu keinem Zeitpunkt den Inhalt eines Führungszeugnisses — erfasst werden ausschließlich Prüfdatum und Prüfergebnis (Datenminimierung, Art. 10 DSGVO / § 26 BDSG)."
        ]} />
      </.guidelines_section>

      <.guidelines_section title="2. Haftung für Erfüllungsgehilfen (§ 278, § 823 BGB)">
        <p>
          Der Provider haftet für das Verhalten der von ihm eingesetzten Personen wie für eigenes
          Verhalten. Das Unterlassen der Prüfung nach § 72a SGB VIII stellt eine
          Sorgfaltspflichtverletzung dar.
        </p>
      </.guidelines_section>

      <.guidelines_section title="3. Meldepflicht (48 Stunden)">
        <p>
          Der Provider verpflichtet sich, Klass Hero innerhalb von 48 Stunden zu benachrichtigen,
          sobald gegen eine mit Minderjährigen betraute Person wegen einer Straftat gegen Kinder
          ermittelt wird.
        </p>
      </.guidelines_section>

      <.guidelines_section title="4. Freistellung und Vertragsstrafe (§ 339 BGB)">
        <p>
          Der Provider stellt Klass Hero von Ansprüchen frei, die aus einer Verletzung dieser
          Erklärung entstehen. Bei schuldhaftem Verstoß gegen die Prüfpflicht wird eine
          Vertragsstrafe in Höhe von
          <span class="font-semibold">€[TODO — pending legal counsel]</span>
          fällig (der Höhe nach angemessen im Sinne des § 343 BGB).
        </p>
      </.guidelines_section>
    </div>
    """
  end

  # The public download path for a given guidelines `version`'s immutable PDF.
  defp community_guidelines_pdf_path(version), do: "/downloads/Klass_Hero_Community_Standards_Agreement_v#{version}.pdf"

  # The verbatim Community Guidelines body (v1.0). Not translated — it is a legal artifact tied to
  # a specific `version`; a localized agreement would be its own versioned text + PDF.
  defp guidelines_body(assigns) do
    ~H"""
    <div class={["space-y-5 leading-relaxed", Theme.typography(:body_small), Theme.text_color(:body)]}>
      <p>
        This Community Standards Agreement ("Agreement") is entered into between the provider named
        below ("Provider") and Klass Hero ("Klass Hero"), a marketplace platform connecting families
        with vetted youth activity providers in Berlin and beyond. By registering as a provider on
        the Klass Hero platform, Provider agrees to be bound by the terms of this Agreement,
        including the Community Guidelines set out herein.
      </p>

      <.guidelines_section title="1. Platform Overview">
        <p>
          Klass Hero is a trusted marketplace for youth activities, including sports, arts, tutoring,
          and enrichment, designed to help families discover high-quality, vetted providers. The
          standards in this Agreement protect children, families, and the integrity of every provider
          on the platform.
        </p>
      </.guidelines_section>

      <.guidelines_section title="2. Provider Eligibility">
        <p>Providers must meet the following baseline requirements to list on Klass Hero:</p>
        <.guidelines_bullets items={[
          "Be 18 years of age or older",
          "Hold any required certifications, qualifications, or licences relevant to their activity",
          "Agree to and pass Klass Hero's background verification process",
          "Maintain valid public liability insurance where applicable",
          "Operate in compliance with all applicable German law and local regulations"
        ]} />
      </.guidelines_section>

      <.guidelines_section title="3. Community Guidelines">
        <h4 class="font-semibold mt-3">3.1 Professionalism</h4>
        <p>
          Providers are representatives of the Klass Hero community and are expected to maintain a
          high standard of professional conduct at all times:
        </p>
        <.guidelines_bullets items={[
          "Arrive punctually and prepared for every session",
          "Communicate clearly and respectfully with families and Klass Hero staff",
          "Present sessions and listings accurately, no misleading descriptions, qualifications, or pricing",
          "Maintain appropriate dress, language, and behaviour when working with children",
          "Respond to messages and booking requests within 48 hours"
        ]} />

        <h4 class="font-semibold mt-3">3.2 Child Safety</h4>
        <p>
          The safety and wellbeing of children is the highest priority on the Klass Hero platform. Providers must:
        </p>
        <.guidelines_bullets items={[
          "Never engage in physical, verbal, emotional, or any other form of abuse towards a minor",
          "Never be alone with a child in a closed, unobserved space without parental consent",
          "Report any safeguarding concerns immediately to a parent/guardian and, where required, relevant authorities",
          "Comply with Klass Hero's Child Safety Policy at all times",
          "Hold relevant child protection training where required by their activity or jurisdiction"
        ]} />

        <h4 class="font-semibold mt-3">3.3 Inclusivity & Non-Discrimination</h4>
        <p>
          Klass Hero is committed to being a welcoming platform for all families. Providers must not
          discriminate against any participant or family on the basis of:
        </p>
        <.guidelines_bullets items={[
          "Race, ethnicity, or national origin",
          "Gender identity or sexual orientation",
          "Disability or health condition",
          "Religion or belief",
          "Socioeconomic background"
        ]} />
        <p>
          Reasonable accommodations for participants with additional needs should be offered wherever possible.
        </p>

        <h4 class="font-semibold mt-3">3.4 Accurate Listings & Honest Representation</h4>
        <.guidelines_bullets items={[
          "All activity listings must accurately reflect the content, duration, age range, and pricing of sessions",
          "Qualifications, certifications, and experience listed must be truthful and verifiable",
          "Promotional materials must not contain false or exaggerated claims",
          "Providers must promptly update listings if details change"
        ]} />

        <h4 class="font-semibold mt-3">3.5 Payment & Booking Integrity</h4>
        <.guidelines_bullets items={[
          "Providers must not solicit or accept payments from families outside the Klass Hero platform for bookings made through the platform",
          "Cancellations must be made in accordance with Klass Hero's Cancellation Policy",
          "Providers must not no-show without advance notice; repeated no-shows may result in suspension"
        ]} />

        <h4 class="font-semibold mt-3">3.6 Data & Privacy</h4>
        <.guidelines_bullets items={[
          "Provider must treat any personal data of families and children accessed via Klass Hero with strict confidentiality",
          "Data may only be used for the purpose of delivering the booked activity",
          "Providers must comply with all applicable data protection laws, including the GDPR"
        ]} />
      </.guidelines_section>

      <.guidelines_section title="4. Reviews & Feedback">
        <p>Klass Hero operates a transparent review system. Providers agree that:</p>
        <.guidelines_bullets items={[
          "Families may leave honest reviews following sessions",
          "Providers must not solicit, manipulate, or misrepresent reviews",
          "Klass Hero may publish reviews on provider profile pages",
          "Providers may respond to reviews professionally and constructively"
        ]} />
      </.guidelines_section>

      <.guidelines_section title="5. Enforcement & Consequences">
        <p>
          Klass Hero reserves the right to investigate complaints and take action proportionate to
          any breach of this Agreement. Potential consequences include:
        </p>
        <.guidelines_bullets items={[
          "Warning notice issued to the Provider",
          "Temporary suspension from the platform",
          "Permanent removal and deactivation of the provider account",
          "Referral to relevant authorities where required by law"
        ]} />
        <p>
          Klass Hero will make reasonable efforts to notify the Provider of any investigation and to
          allow a right of response, except where immediate action is required to protect the safety
          of children or families.
        </p>
      </.guidelines_section>

      <.guidelines_section title="6. Amendments">
        <p>
          Klass Hero may update these Community Standards from time to time. Providers will be
          notified of material changes via email and/or the platform dashboard. Continued use of the
          platform following notice of changes constitutes acceptance of the updated terms.
        </p>
      </.guidelines_section>

      <.guidelines_section title="7. Governing Law">
        <p>
          This Agreement is governed by the laws of the Federal Republic of Germany. Any disputes
          shall be subject to the exclusive jurisdiction of the courts of Berlin.
        </p>
      </.guidelines_section>
    </div>
    """
  end

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp guidelines_section(assigns) do
    ~H"""
    <section class="space-y-2">
      <h3 class={[Theme.typography(:card_title), Theme.text_color(:heading)]}>{@title}</h3>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :items, :list, required: true

  defp guidelines_bullets(assigns) do
    ~H"""
    <ul class="list-disc pl-5 space-y-1">
      <li :for={item <- @items}>{item}</li>
    </ul>
    """
  end
end
