defmodule KlassHero.Participation.Domain.Services.ParticipationCollection do
  @moduledoc """
  Domain service for collection-level operations on participation records.

  Provides pure functions for aggregating and querying collections of
  participation records without database dependencies.
  """

  alias KlassHero.Participation.ParticipationRecord

  @doc """
  Counts records with checked-in status.

  ## Examples

      iex> records = [
      ...>   %ParticipationRecord{status: :checked_in},
      ...>   %ParticipationRecord{status: :registered}
      ...> ]
      iex> ParticipationCollection.count_checked_in(records)
      1
  """
  @spec count_checked_in([ParticipationRecord.t() | map()]) :: non_neg_integer()
  def count_checked_in(records) when is_list(records) do
    Enum.count(records, fn
      %ParticipationRecord{} = record -> ParticipationRecord.checked_in?(record)
      %{status: status} -> status == :checked_in
    end)
  end

  @doc """
  Counts records by status.

  Returns a map with counts for each possible status.

  ## Examples

      iex> records = [
      ...>   %ParticipationRecord{status: :checked_in},
      ...>   %ParticipationRecord{status: :registered},
      ...>   %ParticipationRecord{status: :checked_in}
      ...> ]
      iex> ParticipationCollection.count_by_status(records)
      %{registered: 1, checked_in: 2, checked_out: 0, absent: 0}
  """
  @spec count_by_status([ParticipationRecord.t()]) :: map()
  def count_by_status(records) when is_list(records) do
    initial = %{registered: 0, checked_in: 0, checked_out: 0, absent: 0}

    Enum.reduce(records, initial, fn record, counts ->
      Map.update!(counts, record.status, &(&1 + 1))
    end)
  end
end
