defmodule KlassHero.Participation.Application.Commands.ReviewBehavioralNote do
  @moduledoc """
  Use case for approving or rejecting a behavioral note.

  ## Business Rules

  - Note must exist
  - Note must be in :pending_approval status
  - Decision must be :approve or :reject
  - Rejection reason is optional

  ## Events Published

  - `behavioral_note_approved` on approval
  - `behavioral_note_rejected` on rejection
  """

  alias KlassHero.Participation.Application.Shared
  alias KlassHero.Participation.Domain.Events.ParticipationEvents
  alias KlassHero.Participation.Domain.Models.BehavioralNote
  alias KlassHero.Shared.DomainEventBus

  @context KlassHero.Participation

  @behavioral_note_reader Application.compile_env!(:klass_hero, [
                            :participation,
                            :for_querying_behavioral_notes
                          ])
  @behavioral_note_repository Application.compile_env!(:klass_hero, [
                                :participation,
                                :for_storing_behavioral_notes
                              ])

  @type params :: %{
          required(:note_id) => String.t(),
          required(:parent_id) => String.t(),
          required(:decision) => :approve | :reject,
          optional(:reason) => String.t()
        }

  @type result :: {:ok, BehavioralNote.t()} | {:error, term()}

  @spec execute(params()) :: result()
  def execute(%{note_id: note_id, parent_id: parent_id, decision: decision} = params) do
    reason = Map.get(params, :reason)

    # Scoped query enforces ownership at DB level — returns :not_found if note doesn't belong to parent.
    with {:ok, note} <- @behavioral_note_reader.get_by_id_and_parent(note_id, parent_id),
         {:ok, reviewed} <- apply_decision(note, decision, reason),
         {:ok, persisted} <- @behavioral_note_repository.update(reviewed) do
      Shared.log_publish_result(publish_event(persisted, decision), persisted.id)
      {:ok, persisted}
    end
  end

  defp apply_decision(note, :approve, _reason), do: BehavioralNote.approve(note)
  defp apply_decision(note, :reject, reason), do: BehavioralNote.reject(note, reason)
  defp apply_decision(_note, _decision, _reason), do: {:error, :invalid_decision}

  defp publish_event(note, :approve) do
    event = ParticipationEvents.behavioral_note_approved(note)
    DomainEventBus.dispatch(@context, event)
  end

  defp publish_event(note, :reject) do
    event = ParticipationEvents.behavioral_note_rejected(note)
    DomainEventBus.dispatch(@context, event)
  end
end
