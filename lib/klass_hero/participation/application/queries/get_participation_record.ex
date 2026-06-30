defmodule KlassHero.Participation.Application.Queries.GetParticipationRecord do
  @moduledoc """
  Use case for retrieving a single participation record by ID.
  """

  alias KlassHero.Participation.ParticipationRecord

  @participation_repository Application.compile_env!(:klass_hero, [
                              :participation,
                              :for_querying_participation_records
                            ])

  @type result :: {:ok, ParticipationRecord.t()} | {:error, :not_found}

  @doc """
  Retrieves a participation record by ID.

  ## Parameters

  - `record_id` - ID of the participation record

  ## Returns

  - `{:ok, record}` on success
  - `{:error, :not_found}` if record doesn't exist
  """
  @spec execute(String.t()) :: result()
  def execute(record_id) when is_binary(record_id) do
    @participation_repository.get_by_id(record_id)
  end
end
