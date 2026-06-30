defmodule KlassHero.Participation.Application.Commands.ReviseBehavioralNote do
  @moduledoc """
  Use case for revising a rejected behavioral note.

  ## Business Rules

  - Note must exist
  - Note must be in :rejected status
  - New content must be non-blank and at most 1000 characters

  ## Events Published

  - `behavioral_note_submitted` on successful revision (resubmission)
  """

  alias KlassHero.Participation.Application.Shared
  alias KlassHero.Participation.Domain.Events.ParticipationEvents
  alias KlassHero.Participation.BehavioralNote
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
          required(:provider_id) => String.t(),
          required(:content) => String.t()
        }

  @type result :: {:ok, BehavioralNote.t()} | {:error, term()}

  @spec execute(params()) :: result()
  def execute(%{note_id: note_id, provider_id: provider_id, content: content}) do
    normalized_content = Shared.normalize_notes(content)

    # Scoped query enforces ownership at DB level — returns :not_found if note doesn't belong to provider.
    with {:content, content} when content != nil <- {:content, normalized_content},
         {:ok, note} <- @behavioral_note_reader.get_by_id_and_provider(note_id, provider_id),
         {:ok, revised} <- BehavioralNote.revise(note, content),
         {:ok, persisted} <- @behavioral_note_repository.update(revised) do
      Shared.log_publish_result(publish_event(persisted), persisted.id)
      {:ok, persisted}
    else
      {:content, nil} -> {:error, :blank_content}
      error -> error
    end
  end

  defp publish_event(note) do
    event = ParticipationEvents.behavioral_note_submitted(note)
    DomainEventBus.dispatch(@context, event)
  end
end
