defmodule KlassHero.Participation.Application.Queries.GetBehavioralNoteForRecord do
  @moduledoc """
  Use case for retrieving a behavioral note by participation record and provider.

  Wraps the repository call for facade consistency — all behavioral note
  operations go through use cases.
  """

  alias KlassHero.Participation.BehavioralNote

  @behavioral_note_repository Application.compile_env!(:klass_hero, [
                                :participation,
                                :for_querying_behavioral_notes
                              ])

  @type result :: {:ok, BehavioralNote.t()} | {:error, :not_found}

  @doc """
  Retrieves a behavioral note for a given participation record and provider.

  ## Parameters

  - `record_id` - ID of the participation record
  - `provider_id` - ID of the provider

  ## Returns

  - `{:ok, note}` if found
  - `{:error, :not_found}` if no note exists
  """
  @spec execute(String.t(), String.t()) :: result()
  def execute(record_id, provider_id) when is_binary(record_id) and is_binary(provider_id) do
    @behavioral_note_repository.get_by_participation_record_and_provider(record_id, provider_id)
  end

  @doc """
  Retrieves all behavioral notes for a list of participation records by a single provider.

  Returns a flat list of notes (one per record at most).
  """
  @spec execute_batch([String.t()], String.t()) :: [BehavioralNote.t()]
  def execute_batch(record_ids, provider_id) when is_list(record_ids) and is_binary(provider_id) do
    @behavioral_note_repository.list_by_records_and_provider(record_ids, provider_id)
  end
end
