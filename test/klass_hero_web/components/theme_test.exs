defmodule KlassHeroWeb.ThemeTest do
  use ExUnit.Case, async: true

  alias KlassHeroWeb.Theme

  describe "status_badge/1" do
    @cases [
      {:available, "bg-green-100 text-green-800"},
      {:limited, "bg-yellow-100 text-yellow-800"},
      {:full, "bg-red-100 text-red-800"},
      {:neutral, "bg-hero-grey-100 text-hero-grey-800"}
    ]

    test "returns AA-safe filled (-100/-800) classes for each bucket" do
      for {bucket, expected} <- @cases do
        assert Theme.status_badge(bucket) == expected,
               "expected status_badge(#{inspect(bucket)}) to be #{inspect(expected)}, " <>
                 "got #{inspect(Theme.status_badge(bucket))}"
      end
    end
  end
end
