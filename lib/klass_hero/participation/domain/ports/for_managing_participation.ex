defmodule KlassHero.Participation.Domain.Ports.ForManagingParticipation do
  @moduledoc """
  Write-only port for participation record persistence.

  Defines the contract for participation record write operations (CQRS command side).
  Read operations have been moved to `ForQueryingParticipation`.
  """

  alias KlassHero.Participation.ParticipationRecord

  @doc "Creates participation record. Returns `{:error, :duplicate_record}` on unique violation."
  @callback create(ParticipationRecord.t()) ::
              {:ok, ParticipationRecord.t()} | {:error, :duplicate_record | :validation_failed}

  @doc "Updates existing participation record. Returns `{:error, :stale_data}` on optimistic lock conflict."
  @callback update(ParticipationRecord.t()) ::
              {:ok, ParticipationRecord.t()}
              | {:error, :stale_data | :not_found | :validation_failed}

  @doc "Creates multiple participation records in a batch."
  @callback create_batch([ParticipationRecord.t()]) ::
              {:ok, [ParticipationRecord.t()]} | {:error, :validation_failed}

  @doc """
  Bulk-seeds participation records for a session using insert_all with ON CONFLICT DO NOTHING.

  Returns `{:ok, count}` where count is the number of actually inserted records.
  Duplicates (existing session_id+child_id pairs) are silently skipped.
  """
  @callback seed_batch(session_id :: String.t(), child_ids :: [String.t()]) ::
              {:ok, non_neg_integer()}

  @doc """
  Bulk-marks a set of participation records as absent using a single UPDATE WHERE id IN (...) AND status = :registered.

  Only records with status `:registered` are updated — already checked-in or
  checked-out records are naturally skipped by the WHERE guard.

  Returns `{:ok, count}` where count is the number of actually updated records.
  Returns `{:ok, 0}` immediately when the list is empty.
  """
  @callback mark_absent_batch(record_ids :: [String.t()]) :: {:ok, non_neg_integer()}
end
