defmodule KlassHeroWeb.Provider.Dashboard.ParamsTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias KlassHeroWeb.Provider.Dashboard.Params

  describe "parser round-trip properties" do
    property "parse_integer/1 round-trips any positive integer's string form" do
      check all(n <- positive_integer()) do
        assert Params.parse_integer(Integer.to_string(n)) == n
      end
    end

    property "parse_date/1 round-trips any ISO8601 date string" do
      check all(offset <- integer(-3650..3650)) do
        date = Date.add(~D[2026-01-01], offset)
        assert Params.parse_date(Date.to_iso8601(date)) == date
      end
    end

    property "parse_decimal/1 round-trips non-negative integer strings" do
      check all(n <- non_negative_integer()) do
        assert Decimal.equal?(Params.parse_decimal(Integer.to_string(n)), Decimal.new(n))
      end
    end
  end

  describe "parse_decimal/1" do
    test "parses a valid decimal string" do
      assert Decimal.equal?(Params.parse_decimal("12.50"), Decimal.new("12.50"))
    end

    test "trims surrounding whitespace before parsing" do
      assert Decimal.equal?(Params.parse_decimal("  7  "), Decimal.new("7"))
    end

    test "passes an existing Decimal through untouched" do
      d = Decimal.new("3.14")
      assert Params.parse_decimal(d) == d
    end

    test "returns nil for nil, empty, and non-numeric input" do
      for input <- [nil, "", "abc", "1.2.3", "12abc"] do
        assert Params.parse_decimal(input) == nil, "expected nil for #{inspect(input)}"
      end
    end
  end

  describe "parse_integer/1" do
    test "parses a positive integer string" do
      assert Params.parse_integer("5") == 5
    end

    test "passes an integer through untouched" do
      assert Params.parse_integer(7) == 7
    end

    test "returns nil for nil, empty, zero, negative, and trailing-garbage input" do
      for input <- [nil, "", "0", "-3", "5x"] do
        assert Params.parse_integer(input) == nil, "expected nil for #{inspect(input)}"
      end
    end
  end

  describe "parse_date/1" do
    test "parses an ISO8601 date" do
      assert Params.parse_date("2026-07-07") == ~D[2026-07-07]
    end

    test "returns nil for nil, empty, and malformed input" do
      for input <- [nil, "", "not-a-date", "2026-13-40"] do
        assert Params.parse_date(input) == nil, "expected nil for #{inspect(input)}"
      end
    end
  end

  describe "parse_time/1" do
    test "parses HH:MM from an HTML time input" do
      assert Params.parse_time("14:30") == ~T[14:30:00]
    end

    test "parses HH:MM:SS from a re-rendered Time struct" do
      assert Params.parse_time("14:30:15") == ~T[14:30:15]
    end

    test "returns nil for nil, empty, and malformed input" do
      for input <- [nil, "", "99:99", "noon"] do
        assert Params.parse_time(input) == nil, "expected nil for #{inspect(input)}"
      end
    end
  end

  describe "parse_meeting_days/1" do
    test "keeps non-empty day strings" do
      assert Params.parse_meeting_days(["mon", "", "wed"]) == ["mon", "wed"]
    end

    test "returns [] for nil and non-list input" do
      for input <- [nil, "mon", %{}] do
        assert Params.parse_meeting_days(input) == [], "expected [] for #{inspect(input)}"
      end
    end
  end

  describe "presence/1" do
    test "returns the value when present" do
      assert Params.presence("hi") == "hi"
    end

    test "returns nil for empty string and nil" do
      assert Params.presence("") == nil
      assert Params.presence(nil) == nil
    end
  end

  describe "nil_safe/2" do
    test "applies the function when value is present" do
      assert Params.nil_safe("2026-07-07", &Date.from_iso8601!/1) == ~D[2026-07-07]
    end

    test "short-circuits to nil without calling the function" do
      assert Params.nil_safe(nil, fn _ -> raise "should not be called" end) == nil
    end
  end

  describe "drop_nil_eligibility_at/1" do
    test "drops the key when eligibility_at is nil" do
      assert Params.drop_nil_eligibility_at(%{eligibility_at: nil, foo: 1}) == %{foo: 1}
    end

    test "keeps attrs untouched when eligibility_at is set or absent" do
      set = %{eligibility_at: ~D[2026-07-07], foo: 1}
      assert Params.drop_nil_eligibility_at(set) == set
      assert Params.drop_nil_eligibility_at(%{foo: 1}) == %{foo: 1}
    end
  end
end
