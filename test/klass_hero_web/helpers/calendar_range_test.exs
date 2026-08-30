defmodule KlassHeroWeb.Helpers.CalendarRangeTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias KlassHeroWeb.Helpers.CalendarRange

  # A Saturday, deliberately: the interesting boundary cases are the days that
  # are not Monday, and August 2026 both starts and ends off a week boundary.
  @saturday ~D[2026-08-29]

  describe "range_for/2" do
    test "a day view is that one day" do
      assert CalendarRange.range_for(:day, @saturday) == Date.range(@saturday, @saturday)
    end

    test "a week view runs Monday to Sunday around the focus date" do
      assert CalendarRange.range_for(:week, @saturday) ==
               Date.range(~D[2026-08-24], ~D[2026-08-30])
    end

    # Padded out to whole weeks so the grid is a rectangle -- and so the query
    # covers every cell drawn. An unpadded month range would render leading and
    # trailing days that could never show a session.
    test "a month view pads to whole weeks around the month" do
      assert CalendarRange.range_for(:month, @saturday) ==
               Date.range(~D[2026-07-27], ~D[2026-09-06])
    end

    test "a month that already starts on a Monday is not padded at the front" do
      # 1 June 2026 is a Monday.
      assert %Date.Range{first: ~D[2026-06-01]} = CalendarRange.range_for(:month, ~D[2026-06-15])
    end
  end

  describe "step/3" do
    for {mode, from, forward, back} <- [
          {:day, ~D[2026-08-29], ~D[2026-08-30], ~D[2026-08-28]},
          {:week, ~D[2026-08-29], ~D[2026-09-05], ~D[2026-08-22]},
          {:month, ~D[2026-08-29], ~D[2026-09-29], ~D[2026-07-29]}
        ] do
      test "#{mode} steps a whole #{mode}" do
        assert CalendarRange.step(unquote(mode), unquote(Macro.escape(from)), 1) ==
                 unquote(Macro.escape(forward))

        assert CalendarRange.step(unquote(mode), unquote(Macro.escape(from)), -1) ==
                 unquote(Macro.escape(back))
      end
    end

    # Date.add/2 on a month would overflow; stepping has to clamp to the month's
    # last day rather than spilling into the next one.
    test "a month step clamps to the shorter month rather than spilling over" do
      assert CalendarRange.step(:month, ~D[2026-03-31], -1) == ~D[2026-02-28]
      assert CalendarRange.step(:month, ~D[2026-01-31], 1) == ~D[2026-02-28]
    end
  end

  describe "properties" do
    defp date_generator do
      gen all(offset <- StreamData.integer(-2000..2000)) do
        Date.add(~D[2026-01-01], offset)
      end
    end

    property "every range contains its focus date" do
      check all(date <- date_generator(), mode <- StreamData.member_of([:day, :week, :month])) do
        assert date in CalendarRange.range_for(mode, date)
      end
    end

    property "week and month ranges start on a Monday and end on a Sunday" do
      check all(date <- date_generator(), mode <- StreamData.member_of([:week, :month])) do
        range = CalendarRange.range_for(mode, date)

        assert Date.day_of_week(range.first) == 1
        assert Date.day_of_week(range.last) == 7
      end
    end

    property "a month grid never exceeds six weeks (42 days)" do
      check all(date <- date_generator()) do
        assert Date.diff(CalendarRange.range_for(:month, date).last, CalendarRange.range_for(:month, date).first) + 1 <=
                 42
      end
    end

    # Not an identity on the date for :month -- stepping off a 31st clamps and
    # cannot come back -- but the *period* must be the one we started in.
    property "stepping forward then back returns to the same period" do
      check all(date <- date_generator(), mode <- StreamData.member_of([:day, :week, :month])) do
        round_tripped = mode |> CalendarRange.step(date, 1) |> then(&CalendarRange.step(mode, &1, -1))

        assert CalendarRange.range_for(mode, round_tripped) == CalendarRange.range_for(mode, date)
      end
    end
  end
end
