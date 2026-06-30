defmodule KlassHeroWeb.Presenters.ProgramPresenterTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias KlassHero.ProgramCatalog.Instructor
  alias KlassHero.ProgramCatalog.Program
  alias KlassHero.Shared.Categories
  alias KlassHeroWeb.Presenters.ProgramPresenter

  describe "to_table_view/1" do
    test "program without instructor returns nil assigned_staff and nil enrollment fields" do
      program = build_program(%{instructor: nil})

      result = ProgramPresenter.to_table_view(program)

      assert result.assigned_staff == nil
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

    test "program with instructor populates assigned_staff" do
      instructor = %Instructor{
        id: "instr-1",
        name: "John Doe",
        headshot_url: "https://example.com/photo.jpg"
      }

      program = build_program(%{instructor: instructor})

      result = ProgramPresenter.to_table_view(program)

      assert result.assigned_staff.id == "instr-1"
      assert result.assigned_staff.name == "John Doe"
      assert result.assigned_staff.initials == "JD"
      assert result.assigned_staff.headshot_url == "https://example.com/photo.jpg"
    end

    test "formats integer Decimal price as string" do
      program = build_program(%{price: Decimal.new("99.00")})

      result = ProgramPresenter.to_table_view(program)

      assert result.price == "99.00"
    end

    test "formats fractional Decimal price as string" do
      program = build_program(%{price: Decimal.new("29.99")})

      result = ProgramPresenter.to_table_view(program)

      assert result.price == "29.99"
    end

    test "builds two-letter initials from two-word name" do
      instructor = %Instructor{id: "1", name: "John Doe", headshot_url: nil}
      program = build_program(%{instructor: instructor})

      assert ProgramPresenter.to_table_view(program).assigned_staff.initials == "JD"
    end

    test "builds single-letter initial from single-word name" do
      instructor = %Instructor{id: "1", name: "Madonna", headshot_url: nil}
      program = build_program(%{instructor: instructor})

      assert ProgramPresenter.to_table_view(program).assigned_staff.initials == "M"
    end

    test "takes only first two initials from three-word name" do
      instructor = %Instructor{id: "1", name: "Mary Jane Watson", headshot_url: nil}
      program = build_program(%{instructor: instructor})

      assert ProgramPresenter.to_table_view(program).assigned_staff.initials == "MJ"
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
    test "explicit category mappings" do
      assert ProgramPresenter.humanize_category("arts") == "Arts"
      assert ProgramPresenter.humanize_category("education") == "Education"
      assert ProgramPresenter.humanize_category("sports") == "Sports"
      assert ProgramPresenter.humanize_category("music") == "Music"
    end

    test "fallback capitalizes unknown categories" do
      assert ProgramPresenter.humanize_category("life-skills") == "Life-skills"
      assert ProgramPresenter.humanize_category("camps") == "Camps"
      assert ProgramPresenter.humanize_category("workshops") == "Workshops"
    end

    test "nil returns General" do
      assert ProgramPresenter.humanize_category(nil) == "General"
    end
  end

  describe "icon_name/1" do
    test "returns heroicon name for each valid category" do
      assert ProgramPresenter.icon_name("sports") == "hero-trophy"
      assert ProgramPresenter.icon_name("arts") == "hero-paint-brush"
      assert ProgramPresenter.icon_name("music") == "hero-musical-note"
      assert ProgramPresenter.icon_name("education") == "hero-academic-cap"
      assert ProgramPresenter.icon_name("life-skills") == "hero-light-bulb"
      assert ProgramPresenter.icon_name("camps") == "hero-fire"
      assert ProgramPresenter.icon_name("workshops") == "hero-wrench-screwdriver"
    end

    test "returns fallback for nil" do
      assert ProgramPresenter.icon_name(nil) == "hero-academic-cap"
    end

    test "returns fallback for empty string and logs warning" do
      log =
        capture_log(fn ->
          assert ProgramPresenter.icon_name("") == "hero-academic-cap"
        end)

      assert log =~ "[ProgramPresenter] Unrecognized category"
    end

    test "returns fallback for unknown category and logs warning" do
      log =
        capture_log(fn ->
          assert ProgramPresenter.icon_name("unknown") == "hero-academic-cap"
        end)

      assert log =~ "[ProgramPresenter] Unrecognized category"
      assert log =~ "unknown"
    end

    test "covers all valid categories" do
      for category <- Categories.categories() do
        log =
          capture_log(fn ->
            icon = ProgramPresenter.icon_name(category)

            assert String.starts_with?(icon, "hero-"),
                   "icon_name/1 missing clause for category #{inspect(category)}"
          end)

        refute log =~ "[ProgramPresenter] Unrecognized category",
               "icon_name/1 fell back to default for category #{inspect(category)}"
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

    test "formats single day" do
      program = build_program(%{meeting_days: ["Saturday"]})
      result = ProgramPresenter.format_schedule(program)
      assert result.days == "Sat"
    end

    test "formats three days with ampersand" do
      program = build_program(%{meeting_days: ["Monday", "Wednesday", "Friday"]})
      result = ProgramPresenter.format_schedule(program)
      assert result.days == "Mon, Wed & Fri"
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

    test "shows both years for cross-year date range" do
      program =
        build_program(%{
          meeting_days: ["Monday"],
          start_date: ~D[2026-11-01],
          end_date: ~D[2027-03-15]
        })

      result = ProgramPresenter.format_schedule(program)
      assert result.date_range == "Nov 1, 2026 - Mar 15, 2027"
    end

    test "shows only end year for same-year date range" do
      program =
        build_program(%{
          meeting_days: ["Monday"],
          start_date: ~D[2026-03-01],
          end_date: ~D[2026-06-30]
        })

      result = ProgramPresenter.format_schedule(program)
      assert result.date_range == "Mar 1 - Jun 30, 2026"
    end

    test "shows start date when end date is nil" do
      program =
        build_program(%{
          meeting_days: ["Monday"],
          start_date: ~D[2026-09-01],
          end_date: nil
        })

      result = ProgramPresenter.format_schedule(program)
      assert result.date_range == "From Sep 1, 2026"
    end

    test "formats times crossing AM/PM" do
      program =
        build_program(%{
          meeting_days: ["Saturday"],
          meeting_start_time: ~T[11:00:00],
          meeting_end_time: ~T[13:30:00]
        })

      result = ProgramPresenter.format_schedule(program)
      assert result.times == "11:00 AM - 1:30 PM"
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
      assert result.period == "session"
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

    test "defaults nil price to zero" do
      program = build_program(%{price: nil})

      result = ProgramPresenter.to_card_view(program)

      assert Decimal.equal?(result.price, Decimal.new(0))
    end

    test "uses fallback icon_name when category is nil" do
      program = build_program(%{category: nil})

      result = ProgramPresenter.to_card_view(program)

      assert result.icon_name == "hero-academic-cap"
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

    test "formats times only when no days" do
      program = %{
        meeting_start_time: ~T[09:00:00],
        meeting_end_time: ~T[11:00:00]
      }

      result = ProgramPresenter.format_schedule_brief(program)
      assert result == "9:00 - 11:00 AM"
    end

    test "returns empty string when no scheduling data" do
      result = ProgramPresenter.format_schedule_brief(%{})
      assert result == ""
    end

    test "formats midnight time correctly" do
      program = %{
        meeting_start_time: ~T[00:00:00],
        meeting_end_time: ~T[01:00:00]
      }

      result = ProgramPresenter.format_schedule_brief(program)
      # Midnight renders as "12:00" (12-hour format), not "0:00"
      assert result == "12:00 - 1:00 AM"
    end

    test "formats noon time correctly" do
      program = %{
        meeting_start_time: ~T[12:00:00],
        meeting_end_time: ~T[13:30:00]
      }

      result = ProgramPresenter.format_schedule_brief(program)
      # Noon renders as "12:00" (12-hour format), with PM suffix
      assert result == "12:00 - 1:30 PM"
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

  defp build_program(overrides) do
    defaults = %{
      id: "test-id",
      title: "Test Program",
      description: "A test program",
      category: "arts",
      price: Decimal.new("50.00"),
      instructor: nil,
      meeting_days: [],
      meeting_start_time: nil,
      meeting_end_time: nil,
      start_date: nil,
      end_date: nil
    }

    struct!(Program, Map.merge(defaults, overrides))
  end
end
