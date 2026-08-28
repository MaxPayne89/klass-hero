defmodule KlassHero.Participation.ParticipationCollectionTest do
  @moduledoc """
  Tests for the ParticipationCollection domain service.

  All tests are pure unit tests with no database dependencies.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias KlassHero.Participation.ParticipationCollection
  alias KlassHero.Participation.ParticipationRecord

  doctest ParticipationCollection

  defp record(status) do
    %ParticipationRecord{
      id: Ecto.UUID.generate(),
      session_id: Ecto.UUID.generate(),
      child_id: Ecto.UUID.generate(),
      status: status
    }
  end

  defp build_record(:struct, status), do: record(status)
  defp build_record(:map, status), do: %{status: status}

  defp record_generator do
    gen all(status <- member_of([:registered, :checked_in, :checked_out, :absent])) do
      record(status)
    end
  end

  @count_checked_in_cases [
    {:struct, [], 0, "empty list"},
    {:struct, [:registered, :checked_out, :absent], 0, "no checked-in records"},
    {:struct, [:registered, :checked_in, :checked_in, :checked_out, :absent], 2, "mixed statuses"},
    {:struct, [:checked_in, :checked_in, :checked_in], 3, "all checked in"},
    {:map, [:checked_in, :registered, :checked_in], 2, "plain maps with status key"},
    {:map, [:registered, :checked_out, :absent], 0, "plain maps, none checked in"}
  ]

  describe "count_checked_in/1" do
    test "counts checked_in records across struct and plain-map inputs" do
      for {shape, statuses, expected, label} <- @count_checked_in_cases do
        records = Enum.map(statuses, &build_record(shape, &1))
        assert ParticipationCollection.count_checked_in(records) == expected, label
      end
    end
  end

  # Every row exercises the same contract: tally a list of record statuses
  # into the fixed 4-key {registered, checked_in, checked_out, absent} map.
  @count_by_status_cases [
    {[], %{registered: 0, checked_in: 0, checked_out: 0, absent: 0}, "empty list"},
    {[:registered, :checked_in, :checked_out, :absent], %{registered: 1, checked_in: 1, checked_out: 1, absent: 1},
     "one of each status"},
    {[:registered, :registered, :registered, :checked_in], %{registered: 3, checked_in: 1, checked_out: 0, absent: 0},
     "multiple records, same status"},
    {[:absent, :absent], %{registered: 0, checked_in: 0, checked_out: 0, absent: 2}, "only absent records"}
  ]

  describe "count_by_status/1" do
    test "counts records by status, always returning all four keys" do
      for {statuses, expected, label} <- @count_by_status_cases do
        records = Enum.map(statuses, &record/1)
        assert ParticipationCollection.count_by_status(records) == expected, label
      end
    end
  end

  describe "properties" do
    property "count_by_status totals equal the record count, and its checked_in tally matches count_checked_in/1" do
      check all(records <- list_of(record_generator(), max_length: 20)) do
        counts = ParticipationCollection.count_by_status(records)

        assert Enum.sum(Map.values(counts)) == length(records)
        assert counts.checked_in == ParticipationCollection.count_checked_in(records)
      end
    end
  end
end
