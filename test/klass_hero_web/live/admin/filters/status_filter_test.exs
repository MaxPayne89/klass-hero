defmodule KlassHeroWeb.Admin.Filters.StatusFilterTest do
  use KlassHero.DataCase, async: true

  import Ecto.Query
  import KlassHero.Factory

  alias KlassHero.Enrollment.Enrollment
  alias KlassHero.Repo
  alias KlassHeroWeb.Admin.Filters.StatusFilter

  describe "query/4 status partitioning" do
    setup do
      insert(:enrollment_schema, status: :pending)
      insert(:enrollment_schema, status: :confirmed)
      insert(:enrollment_schema, status: :completed)
      insert(:enrollment_schema, status: :cancelled)
      :ok
    end

    @partitions [
      {["pending"], MapSet.new([:pending])},
      {["confirmed"], MapSet.new([:confirmed])},
      {["completed"], MapSet.new([:completed])},
      {["cancelled"], MapSet.new([:cancelled])},
      {["pending", "confirmed"], MapSet.new([:pending, :confirmed])},
      {[], MapSet.new([:pending, :confirmed, :completed, :cancelled])}
    ]

    test "returns the union of selected status partitions" do
      base = from(e in Enrollment)

      for {keys, expected_statuses} <- @partitions do
        statuses =
          base
          |> StatusFilter.query(:status, keys, %{})
          |> Repo.all()
          |> MapSet.new(& &1.status)

        assert statuses == expected_statuses,
               "filter keys=#{inspect(keys)} expected=#{inspect(MapSet.to_list(expected_statuses))} got=#{inspect(MapSet.to_list(statuses))}"
      end
    end
  end
end
