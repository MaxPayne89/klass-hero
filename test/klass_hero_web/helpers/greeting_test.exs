defmodule KlassHeroWeb.Helpers.GreetingTest do
  @moduledoc """
  Tests for the parent dashboard's time-of-day greeting helper.

  All `DateTime` inputs are UTC; the helper handles the shift to the user's
  display timezone (defaulting to Europe/Berlin) so DST is exercised.
  """

  use ExUnit.Case, async: true

  alias KlassHero.Accounts.User
  alias KlassHeroWeb.Helpers.Greeting

  describe "default_tz/0" do
    test "returns the configured app default" do
      assert Greeting.default_tz() == "Europe/Berlin"
    end
  end

  describe "bucket/2" do
    test "buckets Berlin local hours into morning/afternoon/evening" do
      # Berlin local hour → expected bucket (boundaries inclusive on lower end).
      cases = [
        {0, :evening},
        {4, :evening},
        {5, :morning},
        {11, :morning},
        {12, :afternoon},
        {17, :afternoon},
        {18, :evening},
        {23, :evening}
      ]

      for {hour, expected} <- cases do
        # Construct a known Berlin-local DateTime, then convert back to UTC for the call.
        berlin = DateTime.new!(~D[2026-01-15], Time.new!(hour, 0, 0), "Europe/Berlin")
        utc = DateTime.shift_zone!(berlin, "Etc/UTC")
        assert Greeting.bucket(utc) == expected, "hour #{hour} expected #{expected}"
      end
    end

    test "respects DST when shifting from UTC to Europe/Berlin (winter, CET = UTC+1)" do
      # 2026-01-15 04:30 UTC is 05:30 in Berlin → :morning.
      utc = DateTime.new!(~D[2026-01-15], ~T[04:30:00], "Etc/UTC")
      assert Greeting.bucket(utc) == :morning
    end

    test "respects DST when shifting from UTC to Europe/Berlin (summer, CEST = UTC+2)" do
      # 2026-07-15 03:30 UTC is 05:30 in Berlin → :morning.
      utc = DateTime.new!(~D[2026-07-15], ~T[03:30:00], "Etc/UTC")
      assert Greeting.bucket(utc) == :morning
    end

    test "accepts a custom :tz option for future per-user timezone preferences" do
      # 2026-01-15 12:00 UTC is 04:00 in America/Los_Angeles → :evening.
      utc = DateTime.new!(~D[2026-01-15], ~T[12:00:00], "Etc/UTC")
      assert Greeting.bucket(utc, "America/Los_Angeles") == :evening
    end
  end

  describe "text/1" do
    setup do
      Gettext.put_locale(KlassHeroWeb.Gettext, "en")
      :ok
    end

    test "returns localized greeting for each bucket" do
      assert Greeting.text(:morning) == "Good morning"
      assert Greeting.text(:afternoon) == "Good afternoon"
      assert Greeting.text(:evening) == "Good evening"
    end
  end

  describe "first_name/1" do
    test "returns the first whitespace-delimited token of a user's name" do
      user = user_with_name("Anna Müller")
      assert Greeting.first_name(user) == "Anna"
    end

    test "returns the whole name when it has no whitespace" do
      user = user_with_name("Anna")
      assert Greeting.first_name(user) == "Anna"
    end

    test "trims leading whitespace before extracting" do
      user = user_with_name("  Anna Müller")
      assert Greeting.first_name(user) == "Anna"
    end

    test "returns nil when name is nil" do
      user = user_with_name(nil)
      assert Greeting.first_name(user) == nil
    end

    test "returns nil when name is blank" do
      user = user_with_name("   ")
      assert Greeting.first_name(user) == nil
    end

    test "returns nil when given nil instead of a user" do
      assert Greeting.first_name(nil) == nil
    end
  end

  describe "title/2" do
    setup do
      Gettext.put_locale(KlassHeroWeb.Gettext, "en")
      :ok
    end

    test "appends the first name when present" do
      utc = berlin_utc(~D[2026-01-15], 9, 0)
      user = user_with_name("Anna Müller")
      assert Greeting.title(utc, user: user) == "Good morning, Anna"
    end

    test "drops the comma + name when name is unavailable" do
      utc = berlin_utc(~D[2026-01-15], 9, 0)
      user = user_with_name(nil)
      assert Greeting.title(utc, user: user) == "Good morning"
    end

    test "drops name segment when no user is provided" do
      utc = berlin_utc(~D[2026-01-15], 14, 0)
      assert Greeting.title(utc) == "Good afternoon"
    end
  end

  defp user_with_name(name) do
    %User{id: "11111111-1111-1111-1111-111111111111", email: "x@example.com", name: name}
  end

  defp berlin_utc(date, hour, minute) do
    date
    |> DateTime.new!(Time.new!(hour, minute, 0), "Europe/Berlin")
    |> DateTime.shift_zone!("Etc/UTC")
  end
end
