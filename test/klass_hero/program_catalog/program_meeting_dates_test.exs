defmodule KlassHero.ProgramCatalog.ProgramMeetingDatesTest do
  @moduledoc """
  Expansion of a program's advertised recurring schedule into the concrete dates
  its sessions fall on. Pure — no database.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias KlassHero.ProgramCatalog.Program

  @weekdays ~w(Monday Tuesday Wednesday Thursday Friday Saturday Sunday)
  @weekday_numbers @weekdays |> Enum.with_index(1) |> Map.new()

  @full_schedule %Program{
    meeting_days: ["Monday", "Wednesday"],
    meeting_start_time: ~T[15:00:00],
    meeting_end_time: ~T[17:00:00],
    start_date: ~D[2026-03-02],
    end_date: ~D[2026-03-15]
  }

  describe "meeting_dates/1" do
    test "returns every matching weekday within the range, in order" do
      assert {:ok, dates} = Program.meeting_dates(@full_schedule)

      assert dates == [
               ~D[2026-03-02],
               ~D[2026-03-04],
               ~D[2026-03-09],
               ~D[2026-03-11]
             ]
    end

    test "includes both range endpoints when they match" do
      program = %{@full_schedule | start_date: ~D[2026-03-02], end_date: ~D[2026-03-04]}

      assert {:ok, [~D[2026-03-02], ~D[2026-03-04]]} = Program.meeting_dates(program)
    end

    test "handles a single-day range" do
      # 2026-03-02 is a Monday.
      program = %{@full_schedule | start_date: ~D[2026-03-02], end_date: ~D[2026-03-02]}

      assert {:ok, [~D[2026-03-02]]} = Program.meeting_dates(program)
    end

    test "returns an empty list when no day in the range matches" do
      program = %{@full_schedule | meeting_days: ["Sunday"], start_date: ~D[2026-03-02], end_date: ~D[2026-03-04]}

      assert {:ok, []} = Program.meeting_dates(program)
    end

    test "spans a leap-year February" do
      program = %{
        @full_schedule
        | meeting_days: ["Saturday"],
          start_date: ~D[2028-02-25],
          end_date: ~D[2028-03-01]
      }

      assert {:ok, [~D[2028-02-26]]} = Program.meeting_dates(program)
    end

    for {label, overrides} <- [
          {"no meeting days", %{meeting_days: []}},
          {"nil meeting days", %{meeting_days: nil}},
          {"only unrecognised day names", %{meeting_days: ["Caturday"]}},
          {"no start time", %{meeting_start_time: nil}},
          {"no end time", %{meeting_end_time: nil}},
          {"no start date", %{start_date: nil}},
          {"no end date", %{end_date: nil}}
        ] do
      test "returns :incomplete_schedule with #{label}" do
        program = struct(@full_schedule, unquote(Macro.escape(overrides)))

        assert {:error, :incomplete_schedule} = Program.meeting_dates(program),
               "expected #{unquote(label)} to be treated as an incomplete schedule"
      end
    end

    test "refuses a range that would generate more sessions than the cap" do
      program = %{
        @full_schedule
        | meeting_days: ~w(Monday Tuesday Wednesday Thursday Friday Saturday Sunday),
          start_date: ~D[2026-01-01],
          end_date: ~D[2036-01-01]
      }

      assert {:error, :schedule_range_too_large} = Program.meeting_dates(program)
    end

    property "every returned date matches a requested weekday and sits inside the range" do
      check all(
              day_count <- integer(1..7),
              span <- integer(0..120),
              start_offset <- integer(-200..200)
            ) do
        days = Enum.take(@weekdays, day_count)
        start_date = Date.add(~D[2026-01-01], start_offset)
        end_date = Date.add(start_date, span)
        wanted = MapSet.new(days, &Map.fetch!(@weekday_numbers, &1))

        program = %{@full_schedule | meeting_days: days, start_date: start_date, end_date: end_date}

        assert {:ok, dates} = Program.meeting_dates(program)

        for date <- dates do
          assert Date.day_of_week(date) in wanted
          assert Date.compare(date, start_date) != :lt
          assert Date.compare(date, end_date) != :gt
        end

        assert dates == Enum.sort_by(dates, & &1, Date)
      end
    end

    property "a schedule naming all seven days returns every date in the range" do
      check all(span <- integer(0..90)) do
        start_date = ~D[2026-04-01]
        end_date = Date.add(start_date, span)
        program = %{@full_schedule | meeting_days: @weekdays, start_date: start_date, end_date: end_date}

        assert {:ok, dates} = Program.meeting_dates(program)
        assert length(dates) == span + 1
      end
    end
  end
end
