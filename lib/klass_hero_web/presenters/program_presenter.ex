defmodule KlassHeroWeb.Presenters.ProgramPresenter do
  @moduledoc """
  Presentation layer for transforming Program domain models to UI-ready formats.

  This module follows the DDD/Ports & Adapters pattern by keeping presentation
  concerns in the web layer while the domain model stays pure.

  ## Usage

      alias KlassHeroWeb.Presenters.ProgramPresenter

      # For table views (provider dashboard)
      programs_for_view = Enum.map(programs, &ProgramPresenter.to_table_view/1)
  """

  use Gettext, backend: KlassHeroWeb.Gettext

  alias KlassHero.ProgramCatalog.Domain.Models.Program
  alias KlassHero.ProgramCatalog.Domain.ReadModels.ProgramListing
  alias KlassHero.Shared.NameUtils

  require Logger

  @doc """
  Transforms a Program domain model to table view format.

  Used for the provider dashboard program inventory table.

  Returns a map with: id, name, category, price, assigned_staff, status, enrolled, capacity

  ## Placeholder Values

  The following fields return placeholder values pending feature implementation:

  - `status: :active` - Program status tracking not yet implemented
  - `enrolled: 0` - Enrollment count integration not yet implemented

  These placeholders ensure the UI can render properly while the underlying
  features are developed in future iterations.
  """
  @spec to_table_view(Program.t() | ProgramListing.t(), map()) :: map()
  def to_table_view(program, enrollment_data \\ %{})

  def to_table_view(%Program{} = program, enrollment_data) do
    data = Map.get(enrollment_data, program.id, %{})

    %{
      id: program.id,
      name: program.title,
      category: humanize_category(program.category),
      price: format_price(program.price),
      assigned_staff: format_instructor(program.instructor),
      # Placeholder: Program status tracking pending implementation
      status: :active,
      enrolled: Map.get(data, :enrolled),
      capacity: Map.get(data, :capacity)
    }
  end

  # Trigger: CQRS read model now returns ProgramListing DTOs instead of Program entities
  # Why: read side uses flat instructor_name field, not a nested instructor struct
  # Outcome: same table view shape for UI rendering
  def to_table_view(%ProgramListing{} = listing, enrollment_data) do
    data = Map.get(enrollment_data, listing.id, %{})

    %{
      id: listing.id,
      name: listing.title,
      category: humanize_category(listing.category),
      price: format_price(listing.price),
      assigned_staff: format_listing_instructor(listing),
      status: :active,
      enrolled: Map.get(data, :enrolled),
      capacity: Map.get(data, :capacity)
    }
  end

  @doc """
  Transforms a Program domain model to card view format.

  Used for the parent dashboard's Family Programs section and anywhere
  `<.program_card>` is rendered from real domain data.

  Returns a map matching the attrs expected by `ProgramComponents.program_card/1`.
  """
  @spec to_card_view(Program.t()) :: map()
  def to_card_view(%Program{} = program) do
    %{
      id: program.id,
      title: program.title,
      description: program.description,
      category: humanize_category(program.category),
      age_range: program.age_range,
      # Trigger: program_card calls ProgramCatalog.format_price/1 which expects Decimal.t()
      # Why: converting to string would cause FunctionClauseError at runtime
      # Outcome: price stays as Decimal for safe downstream formatting
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

  # Trigger: no category-specific gradient mapping exists yet
  # Why: a single default gradient keeps the card visually consistent until
  #      category-based theming is implemented
  # Outcome: all cards share the same blue gradient background
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
    # Trigger: no meeting days provided
    # Why: if there's also no start time and no date range, there's nothing to display
    # Outcome: returns nil so UI can hide the schedule section entirely
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
    # Trigger: both times in the same AM/PM period
    # Why: "4:00 - 5:30 PM" reads cleaner than "4:00 PM - 5:30 PM"
    # Outcome: omit period from start time when both share the same period
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

  # Trigger: end_date is nil but start_date exists
  # Why: open-ended programs still benefit from showing when they begin
  # Outcome: displays "From Sep 1, 2026" instead of nil
  defp format_date_range(%Date{} = start_date, nil) do
    "From #{format_short_date(start_date)}, #{start_date.year}"
  end

  defp format_date_range(%Date{} = start_date, %Date{} = end_date) do
    # Trigger: start and end years differ (e.g. Nov 2026 - Mar 2027)
    # Why: omitting start year is ambiguous for cross-year ranges
    # Outcome: "Nov 1, 2026 - Mar 15, 2027" vs "Mar 1 - Jun 30, 2026"
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

  defp format_instructor(nil), do: nil

  defp format_instructor(instructor) do
    %{
      id: instructor.id,
      name: instructor.name,
      initials: NameUtils.initials_from_name(instructor.name),
      headshot_url: instructor.headshot_url
    }
  end

  # Trigger: ProgramListing stores instructor as flat fields, not a nested struct
  # Why: read model denormalizes data for display, no need for separate entity
  # Outcome: builds same shape map for UI rendering from flat fields
  defp format_listing_instructor(%ProgramListing{instructor_name: nil}), do: nil

  defp format_listing_instructor(%ProgramListing{} = listing) do
    %{
      id: nil,
      name: listing.instructor_name,
      initials: NameUtils.initials_from_name(listing.instructor_name),
      headshot_url: listing.instructor_headshot_url
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
