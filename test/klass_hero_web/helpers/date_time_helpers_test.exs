defmodule KlassHeroWeb.Helpers.DateTimeHelpersTest do
  use ExUnit.Case, async: true

  alias KlassHeroWeb.Helpers.DateTimeHelpers

  doctest DateTimeHelpers

  describe "parse_datetime_local/1" do
    test "parses a valid HTML datetime-local value as UTC" do
      assert %DateTime{} = dt = DateTimeHelpers.parse_datetime_local("2026-04-22T14:30")
      assert dt.year == 2026
      assert dt.month == 4
      assert dt.day == 22
      assert dt.hour == 14
      assert dt.minute == 30
      assert dt.second == 0
      assert dt.time_zone == "Etc/UTC"
    end

    test "returns nil for nil input" do
      assert is_nil(DateTimeHelpers.parse_datetime_local(nil))
    end

    test "returns nil for empty string" do
      assert is_nil(DateTimeHelpers.parse_datetime_local(""))
    end

    test "returns nil for malformed input" do
      assert is_nil(DateTimeHelpers.parse_datetime_local("not-a-datetime"))
      assert is_nil(DateTimeHelpers.parse_datetime_local("2026-13-01T14:30"))
    end

    test "returns nil for non-binary input" do
      assert is_nil(DateTimeHelpers.parse_datetime_local(12_345))
      assert is_nil(DateTimeHelpers.parse_datetime_local(%{}))
    end
  end
end
