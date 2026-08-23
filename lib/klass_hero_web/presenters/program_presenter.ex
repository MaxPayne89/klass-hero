defmodule KlassHeroWeb.Presenters.ProgramPresenter do
  @moduledoc """
  Transforms Program domain models to UI-ready formats.
  """

  use Gettext, backend: KlassHeroWeb.Gettext

  alias KlassHero.ProgramCatalog.Program
  alias KlassHero.ProgramCatalog.ProgramListing
  alias KlassHero.Provider.ReadModels.ProgramStaffing
  alias KlassHero.Shared.NameUtils

  require Logger

  @doc """
  Table view for the provider dashboard. `status` is a placeholder (tracking not yet implemented).

  `staffing` is the program's `ProgramStaffing` read-model (or `nil` when nobody
  is on it — the batch read omits those programs), from
  `Provider.list_program_staffing/1`. The single source of truth lives on
  `program_staff_assignments`, not a denormalized program snapshot.

  It carries the whole roster rather than the lead alone because a lead-less but
  staffed program is a sanctioned state that must not render as "Unassigned"
  (#1310). Filtering reads the same read-model through
  `ProgramStaffing.staffed_by?/2` — never this output — so display and
  findability cannot drift apart.
  """
  @spec to_table_view(Program.t() | ProgramListing.t(), map(), ProgramStaffing.t() | nil) :: map()
  def to_table_view(program, enrollment_data \\ %{}, staffing \\ nil)

  def to_table_view(%Program{} = program, enrollment_data, staffing) do
    to_table_row(program.id, program.title, program.category, program.price, enrollment_data, staffing)
  end

  # ProgramListing is a flat read-model DTO used by other list surfaces.
  def to_table_view(%ProgramListing{} = listing, enrollment_data, staffing) do
    to_table_row(listing.id, listing.title, listing.category, listing.price, enrollment_data, staffing)
  end

  defp to_table_row(id, title, category, price, enrollment_data, staffing) do
    data = Map.get(enrollment_data, id, %{})

    %{
      id: id,
      name: title,
      category: humanize_category(category),
      price: format_price(price),
      assigned_staff: format_staffing(staffing),
      status: :active,
      enrolled: Map.get(data, :enrolled),
      capacity: Map.get(data, :capacity)
    }
  end

  @doc """
  Transforms a Program domain model to card view format.

  Used for the parent dashboard's Family Programs section and anywhere
  `<.program_card>` is rendered from real domain data.

  `provider` is the caller's batch-resolved `%{name:, trust:}` for this program's
  provider (see `Provider.get_business_names/1` + `Provider.get_trust_states/1`),
  defaulting to an unnamed, unverified provider so the card degrades to hiding the
  provider row rather than rendering a blank one.

  Returns a map matching the attrs expected by `ProgramComponents.program_card/1`.
  """
  @spec to_card_view(Program.t(), %{name: String.t() | nil, trust: atom()}) :: map()
  def to_card_view(program, provider \\ %{name: nil, trust: :unverified})

  def to_card_view(%Program{} = program, provider) do
    %{
      id: program.id,
      provider_name: provider.name,
      verification_state: provider.trust,
      title: program.title,
      subtitle: program.subtitle,
      description: program.description,
      category: humanize_category(program.category),
      age_range: program.age_range,
      # Keep as Decimal — program_card/format_price expects Decimal.t(), not a string.
      price: if(program.price, do: Decimal.round(program.price, 2), else: Decimal.new(0)),
      period: program.pricing_period,
      icon_name: icon_name(program.category),
      gradient_class: default_gradient_class(),
      meeting_days: program.meeting_days || [],
      meeting_start_time: program.meeting_start_time,
      meeting_end_time: program.meeting_end_time,
      start_date: program.start_date,
      end_date: program.end_date,
      spots_left: nil
    }
  end

  @doc """
  Returns the heroicon name for a given category.

  Used by UI components to render category-appropriate icons.
  Returns a fallback icon for nil or unrecognized categories.

  ## Examples

      iex> KlassHeroWeb.Presenters.ProgramPresenter.icon_name("sports")
      "hero-trophy"

      iex> KlassHeroWeb.Presenters.ProgramPresenter.icon_name(nil)
      "hero-academic-cap"
  """
  @spec icon_name(String.t() | nil) :: String.t()
  def icon_name("sports"), do: "hero-trophy"
  def icon_name("arts"), do: "hero-paint-brush"
  def icon_name("music"), do: "hero-musical-note"
  def icon_name("education"), do: "hero-academic-cap"
  def icon_name("life-skills"), do: "hero-light-bulb"
  def icon_name("camps"), do: "hero-fire"
  def icon_name("workshops"), do: "hero-wrench-screwdriver"
  def icon_name(nil), do: "hero-academic-cap"

  def icon_name(unknown) do
    Logger.warning("[ProgramPresenter] Unrecognized category for icon, using fallback",
      category: unknown
    )

    "hero-academic-cap"
  end

  # Single gradient until category-based theming is implemented.
  defp default_gradient_class do
    "bg-gradient-to-br from-hero-blue-400 to-hero-blue-600"
  end

  @day_abbreviations %{
    "Monday" => "Mon",
    "Tuesday" => "Tue",
    "Wednesday" => "Wed",
    "Thursday" => "Thu",
    "Friday" => "Fri",
    "Saturday" => "Sat",
    "Sunday" => "Sun"
  }

  @doc """
  Formats a program's scheduling fields for display.

  Returns a map with :days, :times, :date_range keys, or nil if no scheduling data.
  """
  @spec format_schedule(Program.t()) ::
          %{days: String.t() | nil, times: String.t() | nil, date_range: String.t() | nil} | nil
  def format_schedule(%Program{meeting_days: days} = program) when days == [] or is_nil(days) do
    # Return nil when there is truly nothing to display; UI hides the section.
    if !(is_nil(program.meeting_start_time) and is_nil(program.start_date)) do
      %{
        days: nil,
        times: format_times(program.meeting_start_time, program.meeting_end_time),
        date_range: format_date_range(program.start_date, program.end_date)
      }
    end
  end

  def format_schedule(%Program{} = program) do
    %{
      days: format_days(program.meeting_days),
      times: format_times(program.meeting_start_time, program.meeting_end_time),
      date_range: format_date_range(program.start_date, program.end_date)
    }
  end

  defp format_days([day]), do: Map.get(@day_abbreviations, day, day)

  defp format_days([d1, d2]) do
    "#{Map.get(@day_abbreviations, d1, d1)} & #{Map.get(@day_abbreviations, d2, d2)}"
  end

  defp format_days(days) when is_list(days) do
    {last, rest} = List.pop_at(days, -1)
    abbreviated = Enum.map(rest, &Map.get(@day_abbreviations, &1, &1))
    "#{Enum.join(abbreviated, ", ")} & #{Map.get(@day_abbreviations, last, last)}"
  end

  defp format_times(nil, _), do: nil
  defp format_times(_, nil), do: nil

  defp format_times(%Time{} = start_time, %Time{} = end_time) do
    # Omit period from start time when same AM/PM: "4:00 - 5:30 PM" vs "4:00 PM - 5:30 PM".
    same_period? = start_time.hour >= 12 == end_time.hour >= 12

    if same_period? do
      "#{format_time_12h(start_time, show_period: false)} - #{format_time_12h(end_time)}"
    else
      "#{format_time_12h(start_time)} - #{format_time_12h(end_time)}"
    end
  end

  defp format_time_12h(time, opts \\ [])

  defp format_time_12h(%Time{hour: hour, minute: minute}, opts) do
    {h12, period} = if hour >= 12, do: {rem(hour, 12), "PM"}, else: {hour, "AM"}
    h12 = if h12 == 0, do: 12, else: h12
    minutes_str = String.pad_leading("#{minute}", 2, "0")

    if Keyword.get(opts, :show_period, true) do
      "#{h12}:#{minutes_str} #{period}"
    else
      "#{h12}:#{minutes_str}"
    end
  end

  defp format_date_range(nil, _), do: nil

  # Open-ended programs show start date only.
  defp format_date_range(%Date{} = start_date, nil) do
    "From #{format_short_date(start_date)}, #{start_date.year}"
  end

  defp format_date_range(%Date{} = start_date, %Date{} = end_date) do
    # Include start year for cross-year ranges to avoid ambiguity.
    if start_date.year == end_date.year do
      "#{format_short_date(start_date)} - #{format_short_date(end_date)}, #{end_date.year}"
    else
      "#{format_short_date(start_date)}, #{start_date.year} - #{format_short_date(end_date)}, #{end_date.year}"
    end
  end

  defp format_short_date(%Date{} = date) do
    month = Enum.at(~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec), date.month - 1)
    "#{month} #{date.day}"
  end

  @doc """
  Formats a brief one-line schedule string from any map with scheduling keys.

  Accepts any map with schedule fields (e.g. component assigns, test data)
  in addition to domain structs. Returns a string like "Mon & Wed 4:00 - 5:30 PM".
  """
  @spec format_schedule_brief(map()) :: String.t()
  def format_schedule_brief(program) when is_map(program) do
    days = Map.get(program, :meeting_days, [])
    start_time = Map.get(program, :meeting_start_time)
    end_time = Map.get(program, :meeting_end_time)

    day_str = if days != [], do: format_days(days)
    time_str = format_times(start_time, end_time)

    [day_str, time_str]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  @doc """
  Formats a brief date range string from any map with :start_date and :end_date keys.

  Returns a string like "Mar 1 - Jun 30, 2026" or nil if no start_date.
  """
  @spec format_date_range_brief(map()) :: String.t() | nil
  def format_date_range_brief(program) when is_map(program) do
    start_date = Map.get(program, :start_date)
    end_date = Map.get(program, :end_date)
    format_date_range(start_date, end_date)
  end

  defp format_price(nil), do: "0.00"
  defp format_price(price), do: price |> Decimal.round(2) |> Decimal.to_string()

  # The table's staff cell. Always a map, so the template branches on values
  # rather than on the presence of the key. `count` is everyone active on the
  # program; `others_count` is everyone who is not the lead — which equals
  # `count` on a leaderless program, so both render branches read the field that
  # means what they need. A nil staffing is an unstaffed program, not missing data.
  defp format_staffing(nil), do: %{lead: nil, count: 0, others_count: 0}

  defp format_staffing(%ProgramStaffing{lead: lead, member_count: count}) do
    %{
      lead: format_lead(lead),
      count: count,
      others_count: if(lead, do: max(count - 1, 0), else: count)
    }
  end

  # Lead instructor (single source of truth on program_staff_assignments), shaped
  # for the dashboard table avatar/name. `initials` is derived here for display.
  defp format_lead(nil), do: nil

  defp format_lead(%{id: id, name: name, headshot_url: headshot_url}) do
    %{
      id: id,
      name: name,
      initials: NameUtils.initials_from_name(name),
      headshot_url: headshot_url
    }
  end

  @doc """
  Formats a category slug for display by splitting on hyphens and capitalizing each word.

  ## Examples

      iex> KlassHeroWeb.Presenters.ProgramPresenter.format_category_for_display("life-skills")
      "Life Skills"

      iex> KlassHeroWeb.Presenters.ProgramPresenter.format_category_for_display(nil)
      "Education"
  """
  @spec format_category_for_display(String.t() | nil) :: String.t()
  def format_category_for_display(category) when is_binary(category) do
    category
    |> String.split("-")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  def format_category_for_display(_), do: "Education"

  @doc """
  Safely converts a Decimal, nil, or unknown value to a float.

  ## Examples

      iex> KlassHeroWeb.Presenters.ProgramPresenter.safe_decimal_to_float(Decimal.new("19.99"))
      19.99

      iex> KlassHeroWeb.Presenters.ProgramPresenter.safe_decimal_to_float(nil)
      0.0
  """
  @spec safe_decimal_to_float(Decimal.t() | nil | term()) :: float()
  def safe_decimal_to_float(nil), do: 0.0
  def safe_decimal_to_float(%Decimal{} = price), do: Decimal.to_float(price)
  def safe_decimal_to_float(_other), do: 0.0

  @doc """
  Transforms a category code to a human-readable label.
  """
  @spec humanize_category(String.t() | nil) :: String.t()
  def humanize_category(nil), do: "General"
  def humanize_category("arts"), do: gettext("Arts")
  def humanize_category("education"), do: gettext("Education")
  def humanize_category("sports"), do: gettext("Sports")
  def humanize_category("music"), do: gettext("Music")
  def humanize_category(category), do: String.capitalize(category)
end
