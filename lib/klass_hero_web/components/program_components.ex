defmodule KlassHeroWeb.ProgramComponents do
  @moduledoc """
  Program-specific components for the program catalog.
  """
  use Phoenix.Component
  use Gettext, backend: KlassHeroWeb.Gettext

  import KlassHeroWeb.UIComponents

  alias KlassHero.ProgramCatalog
  alias KlassHero.Shared.NameUtils
  alias KlassHeroWeb.Presenters.ProgramPresenter
  alias KlassHeroWeb.Theme

  @doc """
  Renders a search input with icon and Klass Hero styling.

  ## Examples

      <.search_bar
        placeholder="Search programs..."
        value={@search_term}
        phx-change="search"
      />
  """
  attr :placeholder, :string, default: nil
  attr :value, :string, default: ""
  attr :name, :string, default: "search"
  attr :class, :string, default: ""
  attr :rest, :global, include: ~w(phx-change phx-submit phx-debounce disabled readonly)

  def search_bar(assigns) do
    assigns = assign_new(assigns, :placeholder, fn -> gettext("Search programs...") end)

    ~H"""
    <div class={["relative", @class]}>
      <input
        type="text"
        name={@name}
        placeholder={@placeholder}
        value={@value}
        class={[
          "w-full px-4 py-3 pl-11 border border-hero-grey-300 focus:outline-none focus:ring-2 focus:ring-hero-blue-500 focus:border-transparent",
          Theme.transition(:normal),
          Theme.rounded(:lg)
        ]}
        {@rest}
      />
      <.icon
        name="hero-magnifying-glass"
        class="absolute left-3 top-1/2 transform -translate-y-1/2 w-5 h-5 text-hero-grey-400"
      />
    </div>
    """
  end

  @doc """
  Renders horizontally scrollable filter pills.

  ## Examples

      <.filter_pills
        filters={[
          %{id: "all", label: "All Programs"},
          %{id: "available", label: "Available"},
          %{id: "ages", label: "By Age"}
        ]}
        active_filter={@current_filter}
        phx-click="filter_select"
      />
  """
  attr :filters, :list,
    required: true,
    doc: "List of filter maps with :id and :label"

  attr :active_filter, :string, required: true, doc: "ID of the currently active filter"
  attr :class, :string, default: ""
  attr :rest, :global, include: ~w(phx-click phx-value-*)

  def filter_pills(assigns) do
    ~H"""
    <div class={["flex gap-2 overflow-x-auto pb-2 scrollbar-hide", @class]}>
      <div class="flex gap-2 min-w-max">
        <button
          :for={filter <- @filters}
          data-filter-id={filter.id}
          data-active={if filter.id == @active_filter, do: "true", else: "false"}
          phx-click={@rest[:"phx-click"]}
          phx-value-filter={filter.id}
          class={[
            "px-4 py-2 text-sm font-medium whitespace-nowrap",
            Theme.transition(:normal),
            Theme.rounded(:full),
            if(filter.id == @active_filter,
              do: "bg-hero-blue-600 text-white shadow-md",
              else:
                "bg-white text-hero-black-100 border border-hero-grey-300 hover:border-hero-grey-400"
            )
          ]}
        >
          {filter.label}
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders horizontally scrollable trending tag pills.

  ## Examples

      <.trending_tags
        tags={["Swimming", "Math Tutor", "Summer Camp", "Piano", "Soccer"]}
      />
  """
  attr :tags, :list, required: true, doc: "List of trending tag strings"
  attr :class, :string, default: ""

  def trending_tags(assigns) do
    ~H"""
    <div class={["flex gap-2 overflow-x-auto pb-2 scrollbar-hide mt-4", @class]}>
      <div class="flex gap-2 min-w-max">
        <span
          :for={tag <- @tags}
          class={[
            "px-3 py-1.5 text-sm font-medium whitespace-nowrap",
            "bg-white/20 backdrop-blur-sm text-white border border-white/30",
            "hover:bg-white/30",
            Theme.transition(:normal),
            Theme.rounded(:full)
          ]}
        >
          {tag}
        </span>
      </div>
    </div>
    """
  end

  @doc """
  Renders a sort dropdown button (visual only, no functionality).

  ## Examples

      <.sort_dropdown selected={@sort_by} />
  """
  attr :selected, :string, default: "Recommended", doc: "Currently selected sort option"
  attr :class, :string, default: ""

  def sort_dropdown(assigns) do
    ~H"""
    <button
      type="button"
      class={[
        "px-4 py-2 bg-white border border-hero-grey-300 text-hero-black-100",
        "hover:border-hero-grey-400 flex items-center gap-2",
        Theme.transition(:normal),
        Theme.rounded(:lg),
        @class
      ]}
    >
      <span class="text-sm font-medium">{@selected}</span>
      <.icon name="hero-chevron-down" class="w-4 h-4" />
    </button>
    """
  end

  @doc """
  Renders view toggle buttons (Grid/List).

  ## Examples

      <.view_toggle active_view={:grid} />
  """
  attr :active_view, :atom, default: :grid, values: [:grid, :list]
  attr :class, :string, default: ""

  def view_toggle(assigns) do
    ~H"""
    <div class={["flex gap-1 bg-hero-grey-100 p-1", Theme.rounded(:lg), @class]}>
      <button
        type="button"
        class={[
          "p-2",
          Theme.transition(:normal),
          Theme.rounded(:md),
          if(@active_view == :grid,
            do: "bg-white text-hero-blue-600 shadow-sm",
            else: "text-hero-grey-500 hover:text-hero-grey-700"
          )
        ]}
      >
        <.icon name="hero-squares-2x2" class="w-5 h-5" />
      </button>
      <button
        type="button"
        disabled
        class={[
          "p-2 opacity-40 cursor-not-allowed",
          Theme.transition(:normal),
          Theme.rounded(:md),
          if(@active_view == :list,
            do: "bg-white text-hero-blue-600 shadow-sm",
            else: "text-hero-grey-500"
          )
        ]}
      >
        <.icon name="hero-bars-3" class="w-5 h-5" />
      </button>
    </div>
    """
  end

  @doc """
  Renders a program card with gradient header, favorite button, and program details.

  Supports two variants:
  - `:detailed` - Full card with all program information (for programs page)
  - `:compact` - Simplified card for homepage or listings

  ## Examples

      <.program_card
        program={@program}
        variant={:detailed}
        phx-click="program_click"
        phx-value-program={@program.title}
      />
  """
  attr :program, :map, required: true
  attr :variant, :atom, default: :detailed, values: [:compact, :detailed]
  attr :class, :string, default: ""
  attr :expired, :boolean, default: false, doc: "Greyed-out styling for expired programs"
  attr :rest, :global, include: ~w(phx-click phx-value-*)
  slot :actions, doc: "Optional action buttons rendered at the bottom of the card"

  def program_card(assigns) do
    ~H"""
    <div
      class={[
        "bg-white shadow-sm border border-hero-grey-100",
        Theme.rounded(:xl),
        if(@expired,
          do: "opacity-60 grayscale",
          else: "hover:shadow-lg hover:scale-[1.02]"
        ),
        Theme.transition(:slow),
        "overflow-hidden cursor-pointer",
        @class
      ]}
      {@rest}
    >
      <%= if Map.get(@program, :cover_image_url) do %>
        <div class="h-48 relative overflow-hidden">
          <img
            id={"program-cover-#{@program.id}"}
            src={@program.cover_image_url}
            alt={@program.title}
            loading="lazy"
            class="w-full h-full object-cover"
          />
          <.card_header_badges program={@program} />
        </div>
      <% else %>
        <div class={["h-48 relative overflow-hidden", @program.gradient_class]}>
          <div class="absolute inset-0 bg-black/10"></div>
          <.card_header_badges program={@program} />

          <div class="absolute inset-0 flex items-center justify-center">
            <div class={[
              "w-16 h-16 bg-white/20 backdrop-blur-sm flex items-center justify-center",
              Theme.rounded(:full)
            ]}>
              <.icon name={@program.icon_name} class="w-8 h-8 text-white" />
            </div>
          </div>
        </div>
      <% end %>

      <div class="p-6">
        <div class="flex items-start justify-between mb-3">
          <div class="flex-1">
            <h3 class={[Theme.typography(:card_title), "text-hero-black mb-2"]}>{@program.title}</h3>
            <p class="text-hero-black-100 text-sm mb-3 line-clamp-2">{@program.description}</p>
          </div>
        </div>

        <%!-- Provider info — renders when provider_name is populated --%>
        <div
          :if={Map.get(@program, :provider_name)}
          class="flex items-center gap-2 mb-4 pb-3 border-b border-hero-grey-100"
        >
          <div class={[
            "w-8 h-8 bg-hero-blue-100 text-hero-blue-600 flex items-center justify-center text-xs font-semibold",
            Theme.rounded(:full)
          ]}>
            {NameUtils.initials_from_name(@program.provider_name)}
          </div>
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-1">
              <span class="text-sm font-medium text-hero-black truncate">
                {@program.provider_name}
              </span>
              <.kh_trust_mark state={Map.get(@program, :verification_state, :unverified)} />
            </div>
            <div
              :if={Map.get(@program, :provider_location)}
              class="text-xs text-hero-grey-500 truncate"
            >
              {@program.provider_location}
            </div>
          </div>
        </div>

        <%!-- Rating & reviews — renders when rating data is populated (pending Review context) --%>
        <div :if={Map.get(@program, :rating)} class="flex items-center gap-2 mb-4">
          <div class="flex items-center">
            <%= for _i <- 1..5 do %>
              <svg class="w-4 h-4 text-yellow-400 fill-current" viewBox="0 0 20 20">
                <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
              </svg>
            <% end %>
          </div>
          <span class="text-sm font-medium text-hero-black">{@program.rating}</span>
          <span
            :if={Map.get(@program, :review_count)}
            class="text-sm text-hero-grey-500"
          >
            ({@program.review_count} reviews)
          </span>
        </div>

        <div class="space-y-2 mb-4">
          <div class="flex items-center text-sm text-hero-black-100">
            <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
              />
            </svg>
            {ProgramPresenter.format_schedule_brief(@program)}
          </div>
          <div
            :if={Map.get(@program, :start_date)}
            class="flex items-center text-sm text-hero-black-100"
          >
            <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"
              />
            </svg>
            {ProgramPresenter.format_date_range_brief(@program)}
          </div>
          <div :if={@program.age_range} class="flex items-center text-sm text-hero-grey-500">
            <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"
              />
            </svg>
            Ages {@program.age_range}
          </div>
        </div>

        <div class="pt-4 border-t border-hero-grey-100">
          <div class={[Theme.typography(:card_title), Theme.text_color(:primary)]}>
            {ProgramCatalog.format_price(@program.price)}
          </div>
          <div class="text-sm text-hero-grey-500">{@program.period}</div>
        </div>
      </div>
      <%= if @actions != [] do %>
        <div class="px-6 pb-6">
          {render_slot(@actions)}
        </div>
      <% end %>
    </div>
    """
  end

  attr :program, :map, required: true

  defp card_header_badges(assigns) do
    ~H"""
    <%!-- Category Badge (top-left) --%>
    <div :if={Map.get(@program, :category)} class="absolute top-4 left-4 z-10">
      <span class={[
        "px-3 py-1 text-xs font-semibold bg-white/90 text-hero-black backdrop-blur-sm",
        Theme.rounded(:full)
      ]}>
        {@program.category}
      </span>
    </div>

    <%!-- ONLINE Badge --%>
    <div :if={Map.get(@program, :is_online, false)} class="absolute top-4 left-4 mt-10 z-10">
      <span class={[
        "px-3 py-1 text-xs font-semibold bg-hero-blue-600 text-white",
        Theme.rounded(:full)
      ]}>
        ONLINE
      </span>
    </div>

    <%!-- Spots Left Badge (bottom-left) --%>
    <.spots_badge
      :if={@program.spots_left && @program.spots_left <= 5}
      spots_left={@program.spots_left}
    />
    """
  end

  @doc """
  Renders a "spots left" badge.

  Shows warning colors based on remaining spots:
  - Red when 2 or fewer spots
  - Orange when 3-5 spots

  ## Examples

      <.spots_badge spots_left={3} />
  """
  attr :spots_left, :integer, required: true
  attr :class, :string, default: ""

  def spots_badge(assigns) do
    ~H"""
    <div class={["absolute bottom-4 left-4", @class]}>
      <span class={[
        "px-2 py-1 text-xs font-medium",
        Theme.rounded(:full),
        if(@spots_left <= 2,
          do: "bg-red-100 text-red-700",
          else: "bg-orange-100 text-orange-700"
        )
      ]}>
        {@spots_left} spots left!
      </span>
    </div>
    """
  end

  @doc """
  Renders a formatted price with currency and period.

  ## Examples

      <.price_display price={45} period="week" />
      <.price_display price={30} period="session" />
      <.price_display price={120} currency="USD" period="month" />
  """
  attr :price, :integer, required: true
  attr :currency, :string, default: "€", doc: "Currency symbol"

  attr :period, :string,
    default: "week",
    values: ~w(week session month hour),
    doc: "Billing period"

  attr :class, :string, default: ""

  def price_display(assigns) do
    ~H"""
    <div class={["text-right", @class]}>
      <div class={[Theme.typography(:section_title), Theme.text_color(:primary)]}>
        {@currency}{@price}
      </div>
      <div class="text-xs text-hero-grey-400">
        per {@period}
      </div>
    </div>
    """
  end

  @doc """
  Renders a read-only card displaying participant restrictions for a program.

  Shows age, gender, and grade restrictions when configured on the policy.

  ## Examples

      <.restriction_info policy={@participant_policy} />
  """
  attr :policy, :map, required: true

  def restriction_info(assigns) do
    ~H"""
    <div
      :if={has_any_restriction?(@policy)}
      class={[
        Theme.bg(:surface),
        Theme.rounded(:xl),
        "shadow-sm border overflow-hidden",
        Theme.border_color(:light)
      ]}
    >
      <div class={["p-4 border-b", Theme.border_color(:light)]}>
        <h3 class={["font-semibold flex items-center gap-2", Theme.text_color(:heading)]}>
          <.icon name="hero-shield-check" class="w-5 h-5 text-hero-blue-500" />
          {gettext("Participant Requirements")}
        </h3>
      </div>
      <div class="p-6">
        <ul class={["space-y-2 text-sm", Theme.text_color(:secondary)]}>
          <li :if={@policy.min_age_months || @policy.max_age_months} class="flex items-start">
            <.icon name="hero-cake" class="w-5 h-5 text-hero-blue-500 mr-2 flex-shrink-0" />
            <span>{format_age_restriction(@policy)}</span>
          </li>
          <li :if={@policy.allowed_genders != []} class="flex items-start">
            <.icon name="hero-users" class="w-5 h-5 text-hero-blue-500 mr-2 flex-shrink-0" />
            <span>{format_gender_restriction(@policy.allowed_genders)}</span>
          </li>
          <li :if={@policy.min_grade || @policy.max_grade} class="flex items-start">
            <.icon name="hero-academic-cap" class="w-5 h-5 text-hero-blue-500 mr-2 flex-shrink-0" />
            <span>{format_grade_restriction(@policy)}</span>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  # Guard: empty heading with no body confuses providers (#795)
  defp has_any_restriction?(%{
         min_age_months: nil,
         max_age_months: nil,
         min_grade: nil,
         max_grade: nil,
         allowed_genders: genders
       })
       when genders in [nil, []], do: false

  defp has_any_restriction?(_policy), do: true

  @doc false
  defp format_age_restriction(%{min_age_months: min, max_age_months: max}) when not is_nil(min) and not is_nil(max) do
    gettext("Ages %{min} to %{max}", min: format_months(min), max: format_months(max))
  end

  defp format_age_restriction(%{min_age_months: min, max_age_months: nil}) when not is_nil(min) do
    gettext("Ages %{min}+", min: format_months(min))
  end

  defp format_age_restriction(%{min_age_months: nil, max_age_months: max}) when not is_nil(max) do
    gettext("Up to %{max}", max: format_months(max))
  end

  # Display "5 years" not "5 years 0 months" when months divide evenly
  defp format_months(months) when rem(months, 12) == 0 do
    years = div(months, 12)
    ngettext("%{count} year", "%{count} years", years)
  end

  defp format_months(months) when months < 12 do
    ngettext("%{count} month", "%{count} months", months)
  end

  defp format_months(months) do
    years = div(months, 12)
    remaining = rem(months, 12)

    years_str = ngettext("%{count} year", "%{count} years", years)
    months_str = ngettext("%{count} month", "%{count} months", remaining)

    "#{years_str} #{months_str}"
  end

  @doc false
  defp format_gender_restriction(genders) when is_list(genders) do
    labels = Enum.map(genders, &humanize_gender/1)

    case labels do
      [single] -> gettext("%{gender} only", gender: single)
      multiple -> Enum.join(multiple, ", ")
    end
  end

  @doc """
  Renders a hero card for an instructor or staff member on the program detail page.

  Accepts a plain prop map so both `Instructor` (sparse: only `id`/`name`/`initials`)
  and `StaffMember` (rich: role/bio/tags/qualifications) can share one component.
  Optional fields are gracefully hidden when `nil` or `[]`.

  ## Examples

      <.hero_card
        id="hero-card-instructor-abc123"
        name="Ada Lovelace"
        initials="AL"
        headshot_url={nil}
        badge="Lead Instructor"
      />
  """
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :initials, :string, required: true
  attr :headshot_url, :string, default: nil
  attr :role, :string, default: nil
  attr :bio, :string, default: nil
  attr :tags, :list, default: []
  attr :qualifications, :list, default: []
  attr :badge, :string, default: nil

  def hero_card(assigns) do
    ~H"""
    <div id={@id} class="flex items-start space-x-4">
      <img
        :if={@headshot_url}
        src={@headshot_url}
        alt={@name}
        class={["w-16 h-16 object-cover flex-shrink-0", Theme.rounded(:full)]}
      />
      <div
        :if={!@headshot_url}
        class={[
          "w-16 h-16 flex items-center justify-center text-white text-xl font-bold flex-shrink-0",
          Theme.rounded(:full),
          Theme.gradient(:primary)
        ]}
      >
        {@initials}
      </div>
      <div class="flex-1">
        <span
          :if={@badge}
          class={[
            "inline-block px-2 py-0.5 mb-1 text-xs font-semibold uppercase tracking-wide bg-hero-blue-100 text-hero-blue-700",
            Theme.rounded(:full)
          ]}
        >
          {@badge}
        </span>
        <h4 class={["font-semibold", Theme.text_color(:heading)]}>
          {@name}
        </h4>
        <p :if={@role} class={["text-sm mb-2", Theme.text_color(:muted)]}>
          {@role}
        </p>
        <p
          :if={@bio}
          class={["text-sm leading-relaxed mb-3", Theme.text_color(:secondary)]}
        >
          {@bio}
        </p>
        <div :if={@tags != []} class="flex flex-wrap gap-1.5 mb-2">
          <span
            :for={tag <- @tags}
            class={[
              "px-2 py-0.5 text-xs font-medium bg-hero-cyan-100 text-hero-cyan",
              Theme.rounded(:full)
            ]}
          >
            {tag}
          </span>
        </div>
        <div :if={@qualifications != []} class="flex flex-wrap gap-1.5">
          <span
            :for={qual <- @qualifications}
            class={[
              "px-2 py-0.5 text-xs font-medium border border-hero-grey-300 text-hero-grey-600",
              Theme.rounded(:md)
            ]}
          >
            {qual}
          </span>
        </div>
      </div>
    </div>
    """
  end

  defp humanize_gender("female"), do: gettext("Female")
  defp humanize_gender("male"), do: gettext("Male")
  defp humanize_gender("diverse"), do: gettext("Diverse")
  defp humanize_gender("not_specified"), do: gettext("Not specified")
  defp humanize_gender(other), do: other

  @doc false
  defp format_grade_restriction(%{min_grade: min, max_grade: max})
       when not is_nil(min) and not is_nil(max) and min == max do
    gettext("Grade %{grade}", grade: min)
  end

  defp format_grade_restriction(%{min_grade: min, max_grade: max}) when not is_nil(min) and not is_nil(max) do
    gettext("Grades %{min} – %{max}", min: min, max: max)
  end

  defp format_grade_restriction(%{min_grade: min, max_grade: nil}) when not is_nil(min) do
    gettext("Grade %{min}+", min: min)
  end

  defp format_grade_restriction(%{min_grade: nil, max_grade: max}) when not is_nil(max) do
    gettext("Up to Grade %{max}", max: max)
  end
end
