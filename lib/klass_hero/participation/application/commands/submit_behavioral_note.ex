defmodule KlassHero.Participation.Application.Commands.SubmitBehavioralNote do
  @moduledoc """
  Use case for submitting a behavioral note about a child's participation.

  ## Business Rules

  - Participation record must exist
  - Record must be in :checked_in or :checked_out status
  - Content must be non-blank and at most 1000 characters
  - One note per provider per participation record (enforced by unique constraint)
  - Parent ID is resolved from the participation record

  ## Events Published

  - `behavioral_note_submitted` on successful submission
  """

  alias KlassHero.Participation.Application.Shared
  alias KlassHero.Participation.Domain.Events.ParticipationEvents
  alias KlassHero.Participation.BehavioralNote
  alias KlassHero.Participation.ParticipationRecord
  alias KlassHero.Shared.DomainEventBus

  @context KlassHero.Participation

  @participation_reader Application.compile_env!(:klass_hero, [
                          :participation,
                          :for_querying_participation_records
                        ])
  @behavioral_note_repository Application.compile_env!(:klass_hero, [
                                :participation,
                                :for_storing_behavioral_notes
                              ])

  @type params :: %{
          required(:participation_record_id) => String.t(),
          required(:provider_id) => String.t(),
          required(:content) => String.t()
        }

  @type result :: {:ok, BehavioralNote.t()} | {:error, term()}

  @spec execute(params()) :: result()
  def execute(%{participation_record_id: record_id, provider_id: provider_id, content: content} = _params) do
    normalized_content = Shared.normalize_notes(content)

    with {:content, content} when content != nil <- {:content, normalized_content},
         {:ok, record} <- @participation_reader.get_by_id(record_id),
         true <- ParticipationRecord.allows_behavioral_note?(record),
         {:ok, note} <- build_note(record, provider_id, content),
         {:ok, persisted} <- @behavioral_note_repository.create(note) do
      Shared.log_publish_result(publish_event(persisted), persisted.id)
      {:ok, persisted}
    else
      {:content, nil} -> {:error, :blank_content}
      false -> {:error, :invalid_record_status}
      error -> error
    end
  end

  defp build_note(record, provider_id, content) do
    BehavioralNote.new(%{
      id: Ecto.UUID.generate(),
      participation_record_id: record.id,
      child_id: record.child_id,
      parent_id: record.parent_id,
      provider_id: provider_id,
      content: content
    })
  end

  defp publish_event(note) do
    event = ParticipationEvents.behavioral_note_submitted(note)
    DomainEventBus.dispatch(@context, event)
  end
end
