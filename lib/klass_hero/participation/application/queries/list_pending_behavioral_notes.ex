defmodule KlassHero.Participation.Application.Queries.ListPendingBehavioralNotes do
  @moduledoc """
  Use case for listing pending behavioral notes for a parent.

  Returns all notes awaiting the parent's review, ordered by submission date descending.
  """

  alias KlassHero.Participation.BehavioralNote

  @behavioral_note_repository Application.compile_env!(:klass_hero, [
                                :participation,
                                :for_querying_behavioral_notes
                              ])

  @type result :: {:ok, [BehavioralNote.t()]}

  @doc """
  Lists pending behavioral notes for a parent.

  ## Parameters

  - `parent_id` - ID of the parent

  ## Returns

  `{:ok, notes}` - List of pending behavioral notes.
  """
  @spec execute(String.t()) :: result()
  def execute(parent_id) when is_binary(parent_id) do
    notes = @behavioral_note_repository.list_pending_by_parent(parent_id)
    {:ok, notes}
  end
end
