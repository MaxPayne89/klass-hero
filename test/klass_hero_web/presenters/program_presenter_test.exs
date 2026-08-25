defmodule KlassHeroWeb.Presenters.ProgramPresenterTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias KlassHero.ProgramCatalog.Program
  alias KlassHero.ProgramCatalog.ProgramListing
  alias KlassHero.Provider.ReadModels.ProgramStaffing
  alias KlassHero.Shared.Categories
  alias KlassHeroWeb.Presenters.ProgramPresenter

  doctest ProgramPresenter

  describe "to_table_view/3" do
    test "no staffing (3rd arg omitted) renders as nobody on the program" do
      program = build_program(%{})

      result = ProgramPresenter.to_table_view(program)

      assert result.assigned_staff == %{lead: nil, count: 0, others_count: 0}
      assert result.status == :active
      assert result.enrolled == nil
      assert result.capacity == nil
    end

    test "populates enrolled/capacity from enrollment_data" do
      program = build_program(%{id: "prog-1"})
      enrollment_data = %{"prog-1" => %{enrolled: 5, capacity: 20}}

      result = ProgramPresenter.to_table_view(program, enrollment_data)

      assert result.enrolled == 5
      assert result.capacity == 20
    end

    test "a lead plus one other yields the lead map and an others_count of 1" do
      staffing =
        staffing(
          members: ["instr-1", "instr-2"],
          lead: %{id: "instr-1", name: "John Doe", headshot_url: "https://example.com/photo.jpg"}
        )

      result = ProgramPresenter.to_table_view(build_program(%{}), %{}, staffing)

      assert result.assigned_staff.lead.id == "instr-1"
      assert result.assigned_staff.lead.name == "John Doe"
      assert result.assigned_staff.lead.initials == "JD"
      assert result.assigned_staff.lead.headshot_url == "https://example.com/photo.jpg"
      assert result.assigned_staff.count == 2
      assert result.assigned_staff.others_count == 1
    end

    # The #1310 state: staffed but leaderless. `count` is what separates it from
    # an empty program, which is the distinction the old lead-only shape lost.
    test "a leaderless but staffed program keeps its headcount with a nil lead" do
      staffing = staffing(members: ["a", "b"], lead: nil)

      result = ProgramPresenter.to_table_view(build_program(%{}), %{}, staffing)

      assert result.assigned_staff.lead == nil
      assert result.assigned_staff.count == 2
      assert result.assigned_staff.others_count == 2
    end

    test "a lone lead has no others" do
      staffing = staffing(members: ["solo"], lead: %{id: "solo", name: "Ada Lovelace", headshot_url: nil})

      result = ProgramPresenter.to_table_view(build_program(%{}), %{}, staffing)

      assert result.assigned_staff.count == 1
      assert result.assigned_staff.others_count == 0
    end

    # {price, expected string} — the table renders the same label every other price
    # surface does, so a provider reads "Free" on their own free program.
    @price_cases [
      {Decimal.new("99.00"), "€99.00"},
      {Decimal.new("29.99"), "€29.99"},
      {Decimal.new("0"), "Free"},
      {nil, "N/A"}
    ]

    for {price, expected} <- @price_cases do
      @price price
      @expected expected
      test "formats Decimal price #{inspect(price)} as #{inspect(expected)}" do
        program = build_program(%{price: @price})

        result = ProgramPresenter.to_table_view(program)

        assert result.price == @expected
      end
    end

    # {name, expected initials} — exercises NameUtils.initials_from_name via the lead map.
    @initials_cases [
      {"John Doe", "JD"},
      {"Madonna", "M"},
      {"Mary Jane Watson", "MJ"}
    ]

    for {name, expected} <- @initials_cases do
      @name name
      @expected expected
      test "#{inspect(name)} -> initials #{inspect(expected)}" do
        staffing = staffing(members: ["1"], lead: %{id: "1", name: @name, headshot_url: nil})
        program = build_program(%{})

        assert ProgramPresenter.to_table_view(program, %{}, staffing).assigned_staff.lead.initials ==
                 @expected
      end
    end

    test "maps program id, name, category, and capacity" do
      program =
        build_program(%{
          id: "prog-1",
          title: "Summer Camp",
          category: "sports"
        })

      result = ProgramPresenter.to_table_view(program)

      assert result.id == "prog-1"
      assert result.name == "Summer Camp"
      assert result.category == "Sports"
      assert result.capacity == nil
    end
  end

  describe "humanize_category/1" do
    # {category, expected label} — every category in Shared.Categories, plus nil and
    # an unknown value exercising the hyphen-aware fallback.
    @category_cases [
      {nil, "General"},
      {"arts", "Arts"},
      {"education", "Education"},
      {"sports", "Sports"},
      {"music", "Music"},
      {"life-skills", "Life Skills"},
      {"camps", "Camps"},
      {"workshops", "Workshops"},
      {"water-sports-club", "Water Sports Club"}
    ]

    for {category, expected} <- @category_cases do
      @category category
      @expected expected
      test "#{inspect(category)} -> #{inspect(expected)}" do
        assert ProgramPresenter.humanize_category(@category) == @expected
      end
    end

    test "every category in the shared list has an explicit clause" do
      # The fallback only formats; it cannot translate. A category reaching it is
      # rendered untranslated in German, silently.
      for category <- Categories.categories() do
        refute ProgramPresenter.humanize_category(category) =~ "-",
               "#{inspect(category)} fell through to the formatting fallback"
      end
    end
  end

  describe "icon_name/1" do
    # {category, expected icon} — every category in the shared Categories list.
    @icon_cases [
      {"sports", "hero-trophy"},
      {"arts", "hero-paint-brush"},
      {"music", "hero-musical-note"},
      {"education", "hero-academic-cap"},
      {"life-skills", "hero-light-bulb"},
      {"camps", "hero-fire"},
      {"workshops", "hero-wrench-screwdriver"}
    ]

    for {category, icon} <- @icon_cases do
      @category category
      @icon icon
      test "#{inspect(category)} -> #{inspect(icon)}" do
        assert ProgramPresenter.icon_name(@category) == @icon
      end
    end

    test "table covers every category in the shared Categories list" do
      table_categories = @icon_cases |> Enum.map(&elem(&1, 0)) |> Enum.sort()
      assert table_categories == Enum.sort(Categories.categories())
    end

    test "returns fallback for nil" do
      assert ProgramPresenter.icon_name(nil) == "hero-academic-cap"
    end

    for unrecognized <- ["", "unknown"] do
      @unrecognized unrecognized
      test "#{inspect(unrecognized)} falls back to hero-academic-cap and logs a warning" do
        log =
          capture_log(fn ->
            assert ProgramPresenter.icon_name(@unrecognized) == "hero-academic-cap"
          end)

        assert log =~ "[ProgramPresenter] Unrecognized category"
        assert log =~ @unrecognized
      end
    end
  end

  describe "format_schedule/1" do
    test "formats full schedule with days, times, and dates" do
      program =
        build_program(%{
          meeting_days: ["Monday", "Wednesday"],
          meeting_start_time: ~T[16:00:00],
          meeting_end_time: ~T[17:30:00],
          start_date: ~D[2026-03-01],
          end_date: ~D[2026-06-30]
        })

      result = ProgramPresenter.format_schedule(program)
      assert result.days == "Mon & Wed"
      assert result.times == "4:00 - 5:30 PM"
      assert result.date_range =~ "Mar 1"
      assert result.date_range =~ "Jun 30"
    end

    test "returns nil when no scheduling data" do
      program = build_program(%{meeting_days: [], meeting_start_time: nil})
      assert ProgramPresenter.format_schedule(program) == nil
    end

    # {meeting_days, expected days string} — single day, two days ("&"), three+ days (", " + "&").
    @day_cases [
      {["Saturday"], "Sat"},
      {["Monday", "Wednesday"], "Mon & Wed"},
      {["Monday", "Wednesday", "Friday"], "Mon, Wed & Fri"}
    ]

    for {days, expected} <- @day_cases do
      @days days
      @expected expected
      test "#{inspect(days)} -> #{inspect(expected)}" do
        program = build_program(%{meeting_days: @days})
        result = ProgramPresenter.format_schedule(program)
        assert result.days == @expected
      end
    end

    test "formats days only when no times set" do
      program =
        build_program(%{
          meeting_days: ["Monday", "Wednesday"],
          meeting_start_time: nil,
          meeting_end_time: nil
        })

      result = ProgramPresenter.format_schedule(program)
      assert result.days == "Mon & Wed"
      assert result.times == nil
    end

    # {start_date, end_date, expected date_range} — cross-year, same-year, open-ended.
    @date_range_cases [
      {~D[2026-11-01], ~D[2027-03-15], "Nov 1, 2026 - Mar 15, 2027"},
      {~D[2026-03-01], ~D[2026-06-30], "Mar 1 - Jun 30, 2026"},
      {~D[2026-09-01], nil, "From Sep 1, 2026"}
    ]

    for {start_date, end_date, expected} <- @date_range_cases do
      @start_date start_date
      @end_date end_date
      @expected expected
      test "#{inspect(start_date)}..#{inspect(end_date)} -> #{inspect(expected)}" do
        program = build_program(%{meeting_days: ["Monday"], start_date: @start_date, end_date: @end_date})
        result = ProgramPresenter.format_schedule(program)
        assert result.date_range == @expected
      end
    end
  end

  describe "to_card_view/3 across both program shapes" do
    test "carries the cover image from a write-model program" do
      # Omitted until now, so the parent dashboard's family-programs cards fell
      # back to the gradient placeholder even for programs that had a cover.
      program = build_program(%{cover_image_url: "https://cdn.example.com/cover.png"})

      assert ProgramPresenter.to_card_view(program).cover_image_url ==
               "https://cdn.example.com/cover.png"
    end

    test "builds the same card keys from a read-model listing" do
      listing = %ProgramListing{
        id: "listing-1",
        title: "Art Adventures",
        description: "Creative art for kids",
        category: "arts",
        age_range: "6-12",
        price: Decimal.new("15.00"),
        cover_image_url: "https://cdn.example.com/cover.png",
        meeting_days: ["Monday"],
        start_date: ~D[2026-03-01],
        end_date: ~D[2026-06-30]
      }

      program = build_program(%{id: "listing-1", title: "Art Adventures"})

      # The point of the shared builder: the two surfaces cannot drift on which
      # keys a card gets, only on the values behind them.
      assert Map.keys(ProgramPresenter.to_card_view(listing)) ==
               Map.keys(ProgramPresenter.to_card_view(program))

      assert ProgramPresenter.to_card_view(listing).cover_image_url ==
               "https://cdn.example.com/cover.png"
    end

    test "renders a hyphenated category as words on both shapes" do
      # Key-parity assertions cannot see this. Folding the two per-LiveView card
      # builders into one swapped which category formatter backs the card, and
      # "Life Skills" became "Life-skills" on three pages with every test green.
      listing = %ProgramListing{id: "l", title: "T", category: "life-skills"}
      program = build_program(%{category: "life-skills"})

      assert ProgramPresenter.to_card_view(listing).category == "Life Skills"
      assert ProgramPresenter.to_card_view(program).category == "Life Skills"
    end

    test "threads spots_left through, defaulting to nil" do
      listing = %ProgramListing{id: "l", title: "T", category: "arts"}

      assert ProgramPresenter.to_card_view(listing).spots_left == nil
      assert ProgramPresenter.to_card_view(listing, %{name: nil, trust: :unverified}, 3).spots_left == 3
    end
  end

  describe "to_card_view/1" do
    test "transforms program domain model to card-ready map" do
      program =
        build_program(%{
          id: "prog-1",
          title: "Art Adventures",
          description: "Creative art for kids",
          category: "arts",
          age_range: "6-12",
          price: Decimal.new("15.00"),
          pricing_period: "session",
          meeting_days: ["Monday", "Wednesday"],
          meeting_start_time: ~T[15:00:00],
          meeting_end_time: ~T[16:30:00],
          start_date: ~D[2026-03-01],
          end_date: ~D[2026-06-30]
        })

      result = ProgramPresenter.to_card_view(program)

      assert result.id == "prog-1"
      assert result.title == "Art Adventures"
      assert result.description == "Creative art for kids"
      assert result.category == "Arts"
      assert result.age_range == "6-12"
      assert Decimal.equal?(result.price, Decimal.new("15.00"))
      refute Map.has_key?(result, :period)
      assert result.icon_name == "hero-paint-brush"
      assert result.meeting_days == ["Monday", "Wednesday"]
      assert result.meeting_start_time == ~T[15:00:00]
      assert result.meeting_end_time == ~T[16:30:00]
      assert result.start_date == ~D[2026-03-01]
      assert result.end_date == ~D[2026-06-30]
      assert is_binary(result.gradient_class)
      assert is_nil(result.spots_left)
    end

    test "derives icon_name from category" do
      program = build_program(%{category: "sports"})

      result = ProgramPresenter.to_card_view(program)

      assert result.icon_name == "hero-trophy"
    end

    test "defaults meeting_days to empty list when nil" do
      program = build_program(%{meeting_days: nil})

      result = ProgramPresenter.to_card_view(program)

      assert result.meeting_days == []
    end

    test "humanizes category" do
      program = build_program(%{category: "sports"})

      result = ProgramPresenter.to_card_view(program)

      assert result.category == "Sports"
    end

    test "keeps price as Decimal" do
      program = build_program(%{price: Decimal.new("29.99")})

      result = ProgramPresenter.to_card_view(program)

      assert Decimal.equal?(result.price, Decimal.new("29.99"))
    end

    test "passes a nil price through rather than coercing it to zero" do
      program = build_program(%{price: nil})

      result = ProgramPresenter.to_card_view(program)

      # Coercing to zero here would make the card label an unpriced program
      # "Free" — a claim about money, not a missing value.
      assert result.price == nil
    end

    test "uses fallback icon_name when category is nil" do
      program = build_program(%{category: nil})

      result = ProgramPresenter.to_card_view(program)

      assert result.icon_name == "hero-academic-cap"
    end
  end

  describe "price_label/1" do
    @labels [
      {nil, "N/A", "unpriced — the program is incomplete, not free"},
      {"0", "Free", "an integral zero"},
      {"0.00", "Free", "a zero carrying scale"},
      {"45.00", "€45.00", "a plain amount"},
      {"45.5", "€45.50", "padded to the cent — the old formatter rendered this as €45.5"},
      {"1234.567", "€1234.57", "rounded to the cent"}
    ]

    test "labels every price state" do
      for {price, expected, why} <- @labels do
        actual = ProgramPresenter.price_label(price && Decimal.new(price))

        assert actual == expected, "#{inspect(price)} (#{why}) should label as #{expected}"
      end
    end

    test "translates the free label" do
      Gettext.put_locale(KlassHeroWeb.Gettext, "de")
      on_exit(fn -> Gettext.put_locale(KlassHeroWeb.Gettext, "en") end)

      assert ProgramPresenter.price_label(Decimal.new("0")) == "Kostenlos"
    end

    test "leaves a priced amount untranslated — a currency string is not prose" do
      Gettext.put_locale(KlassHeroWeb.Gettext, "de")
      on_exit(fn -> Gettext.put_locale(KlassHeroWeb.Gettext, "en") end)

      assert ProgramPresenter.price_label(Decimal.new("45.00")) == "€45.00"
    end
  end

  describe "format_date_range_brief/1" do
    test "formats date range from map" do
      program = %{start_date: ~D[2026-03-01], end_date: ~D[2026-06-30]}
      assert ProgramPresenter.format_date_range_brief(program) == "Mar 1 - Jun 30, 2026"
    end

    test "formats open-ended range" do
      program = %{start_date: ~D[2026-03-01], end_date: nil}
      assert ProgramPresenter.format_date_range_brief(program) == "From Mar 1, 2026"
    end

    test "returns nil when no start_date" do
      assert ProgramPresenter.format_date_range_brief(%{start_date: nil, end_date: nil}) == nil
    end
  end

  describe "format_schedule_brief/1" do
    test "formats days and times from a map" do
      program = %{
        meeting_days: ["Monday", "Wednesday"],
        meeting_start_time: ~T[16:00:00],
        meeting_end_time: ~T[17:30:00]
      }

      result = ProgramPresenter.format_schedule_brief(program)
      assert result == "Mon & Wed 4:00 - 5:30 PM"
    end

    test "formats days only when no times" do
      program = %{meeting_days: ["Saturday"]}
      result = ProgramPresenter.format_schedule_brief(program)
      assert result == "Sat"
    end

    test "returns empty string when no scheduling data" do
      result = ProgramPresenter.format_schedule_brief(%{})
      assert result == ""
    end

    # {start_time, end_time, expected} — times-only maps (no days), exercising the
    # shared time formatter: plain AM range, midnight/noon 12-hour rollover, AM/PM crossing.
    @time_cases [
      {~T[09:00:00], ~T[11:00:00], "9:00 - 11:00 AM"},
      {~T[00:00:00], ~T[01:00:00], "12:00 - 1:00 AM"},
      {~T[12:00:00], ~T[13:30:00], "12:00 - 1:30 PM"},
      {~T[11:00:00], ~T[13:30:00], "11:00 AM - 1:30 PM"}
    ]

    for {start_time, end_time, expected} <- @time_cases do
      @start_time start_time
      @end_time end_time
      @expected expected
      test "#{inspect(start_time)}..#{inspect(end_time)} -> #{inspect(expected)}" do
        program = %{meeting_start_time: @start_time, meeting_end_time: @end_time}
        result = ProgramPresenter.format_schedule_brief(program)
        assert result == @expected
      end
    end

    test "works with domain struct" do
      program =
        build_program(%{
          meeting_days: ["Tuesday", "Thursday"],
          meeting_start_time: ~T[14:00:00],
          meeting_end_time: ~T[15:00:00]
        })

      result = ProgramPresenter.format_schedule_brief(program)
      assert result == "Tue & Thu 2:00 - 3:00 PM"
    end
  end

  defp staffing(opts) do
    members = Keyword.fetch!(opts, :members)

    %ProgramStaffing{
      program_id: "prog-1",
      lead: Keyword.fetch!(opts, :lead),
      member_ids: members,
      member_count: length(members)
    }
  end

  defp build_program(overrides) do
    defaults = %{
      id: "test-id",
      title: "Test Program",
      description: "A test program",
      category: "arts",
      price: Decimal.new("50.00"),
      meeting_days: [],
      meeting_start_time: nil,
      meeting_end_time: nil,
      start_date: nil,
      end_date: nil
    }

    struct!(Program, Map.merge(defaults, overrides))
  end
end
