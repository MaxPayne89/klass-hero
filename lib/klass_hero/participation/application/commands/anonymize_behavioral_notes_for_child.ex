defmodule KlassHero.Participation.Application.Commands.AnonymizeBehavioralNotesForChild do
  @moduledoc """
  Use case for anonymizing all behavioral notes belonging to a child.

  Invoked during GDPR account deletion to replace note content with a
  generic removal message, clear rejection reasons, and set status to
  :rejected. Delegates the definition of "anonymized" to the domain model.
  """

  alias KlassHero.Participation.BehavioralNote

  @behavioral_note_repository Application.compile_env!(:klass_hero, [
                                :participation,
                                :for_storing_behavioral_notes
                              ])

  @type result :: {:ok, non_neg_integer()}

  @doc """
  Anonymizes all behavioral notes for the given child.

  ## Parameters

  - `child_id` - ID of the child whose notes should be anonymized

  ## Returns

  `{:ok, count}` - Number of notes anonymized.
  """
  @spec execute(String.t()) :: result()
  def execute(child_id) when is_binary(child_id) do
    @behavioral_note_repository.anonymize_all_for_child(
      child_id,
      BehavioralNote.anonymized_attrs()
    )
  end
end
