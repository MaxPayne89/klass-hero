defmodule KlassHero.Participation.Domain.Services.ParticipationCollectionTest do
  @moduledoc """
  Tests for the ParticipationCollection domain service.

  All tests are pure unit tests with no database dependencies.
  """

  use ExUnit.Case, async: true

  alias KlassHero.Participation.ParticipationRecord
  alias KlassHero.Participation.Domain.Services.ParticipationCollection

  defp record(status) do
    %ParticipationRecord{
      id: Ecto.UUID.generate(),
      session_id: Ecto.UUID.generate(),
      child_id: Ecto.UUID.generate(),
      status: status
    }
  end

  describe "count_checked_in/1" do
    test "returns 0 for empty list" do
      assert ParticipationCollection.count_checked_in([]) == 0
    end

    test "returns 0 when no records are checked in" do
      records = [record(:registered), record(:checked_out), record(:absent)]
      assert ParticipationCollection.count_checked_in(records) == 0
    end

    test "counts only checked_in records among mixed statuses" do
      records = [
        record(:registered),
        record(:checked_in),
        record(:checked_in),
        record(:checked_out),
        record(:absent)
      ]

      assert ParticipationCollection.count_checked_in(records) == 2
    end

    test "counts all when all records are checked in" do
      records = [record(:checked_in), record(:checked_in), record(:checked_in)]
      assert ParticipationCollection.count_checked_in(records) == 3
    end

    test "accepts plain maps with status key" do
      records = [%{status: :checked_in}, %{status: :registered}, %{status: :checked_in}]
      assert ParticipationCollection.count_checked_in(records) == 2
    end

    test "returns 0 for plain maps with non-checked-in statuses" do
      records = [%{status: :registered}, %{status: :checked_out}, %{status: :absent}]
      assert ParticipationCollection.count_checked_in(records) == 0
    end
  end

  describe "count_by_status/1" do
    test "returns all zeros for empty list" do
      assert ParticipationCollection.count_by_status([]) == %{
               registered: 0,
               checked_in: 0,
               checked_out: 0,
               absent: 0
             }
    end

    test "counts one record of each status" do
      records = [
        record(:registered),
        record(:checked_in),
        record(:checked_out),
        record(:absent)
      ]

      assert ParticipationCollection.count_by_status(records) == %{
               registered: 1,
               checked_in: 1,
               checked_out: 1,
               absent: 1
             }
    end

    test "counts multiple records with the same status" do
      records = [
        record(:registered),
        record(:registered),
        record(:registered),
        record(:checked_in)
      ]

      result = ParticipationCollection.count_by_status(records)
      assert result.registered == 3
      assert result.checked_in == 1
      assert result.checked_out == 0
      assert result.absent == 0
    end

    test "result always contains all four status keys" do
      result = ParticipationCollection.count_by_status([record(:checked_in)])

      assert Map.has_key?(result, :registered)
      assert Map.has_key?(result, :checked_in)
      assert Map.has_key?(result, :checked_out)
      assert Map.has_key?(result, :absent)
    end

    test "counts only absent records correctly" do
      records = [record(:absent), record(:absent)]
      result = ParticipationCollection.count_by_status(records)

      assert result.absent == 2
      assert result.registered == 0
      assert result.checked_in == 0
      assert result.checked_out == 0
    end
  end
end
