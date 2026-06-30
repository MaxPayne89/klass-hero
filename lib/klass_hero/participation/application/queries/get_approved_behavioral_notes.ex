defmodule KlassHero.Participation.Application.Queries.GetApprovedBehavioralNotes do
  @moduledoc """
  Use case for retrieving approved behavioral notes for a child.

  Returns all approved notes, ordered by submission date descending.
  Used in roster views to display historical behavioral observations.
  """

  alias KlassHero.Participation.BehavioralNote

  @behavioral_note_repository Application.compile_env!(:klass_hero, [
                                :participation,
                                :for_querying_behavioral_notes
                              ])

  @type result :: {:ok, [BehavioralNote.t()]}

  @doc """
  Gets approved behavioral notes for a child.

  ## Parameters

  - `child_id` - ID of the child

  ## Returns

  `{:ok, notes}` - List of approved behavioral notes.
  """
  @spec execute(String.t()) :: result()
  def execute(child_id) when is_binary(child_id) do
    notes = @behavioral_note_repository.list_approved_by_child(child_id)
    {:ok, notes}
  end
end
