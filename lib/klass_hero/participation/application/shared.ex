defmodule KlassHero.Participation.Application.Shared do
  @moduledoc """
  Shared utilities for Participation use cases.
  """

  alias KlassHero.Participation.ParticipationRecord
  alias KlassHero.Participation.ProgramSession
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.DomainEventBus

  require Logger

  @context KlassHero.Participation

  @participation_reader Application.compile_env!(:klass_hero, [
                          :participation,
                          :for_querying_participation_records
                        ])
  @participation_repository Application.compile_env!(:klass_hero, [
                              :participation,
                              :for_storing_participation_records
                            ])

  @session_reader Application.compile_env!(:klass_hero, [:participation, :for_querying_sessions])

  @doc """
  Normalizes notes by trimming whitespace and converting empty strings to nil.

  ## Examples

      iex> normalize_notes(nil)
      nil

      iex> normalize_notes("  hello  ")
      "hello"

      iex> normalize_notes("   ")
      nil
  """
  @spec normalize_notes(String.t() | nil) :: String.t() | nil
  def normalize_notes(nil), do: nil

  def normalize_notes(notes) when is_binary(notes) do
    case String.trim(notes) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  @doc """
  Runs the shared attendance action pipeline: fetch → domain call → persist → fetch session → publish event.

  Session is fetched after persisting so the event payload can include `program_id` for
  provider-specific PubSub topic routing.
  """
  @type domain_fn ::
          (ParticipationRecord.t(), String.t(), String.t() | nil ->
             {:ok, ParticipationRecord.t()} | {:error, term()})
  @type event_fn :: (ParticipationRecord.t(), ProgramSession.t() | nil -> DomainEvent.t())

  @spec run_attendance_action(String.t(), String.t(), String.t() | nil, domain_fn(), event_fn()) ::
          {:ok, ParticipationRecord.t()} | {:error, term()}
  def run_attendance_action(record_id, actor_id, notes, domain_fn, event_fn) do
    notes = normalize_notes(notes)

    with {:ok, record} <- @participation_reader.get_by_id(record_id),
         {:ok, updated} <- domain_fn.(record, actor_id, notes),
         {:ok, persisted} <- @participation_repository.update(updated) do
      # Best-effort: attendance already succeeded; session fetch failure must not surface as an error.
      session =
        case @session_reader.get_by_id(persisted.session_id) do
          {:ok, session} ->
            session

          {:error, reason} ->
            Logger.warning("[Participation.Shared] Session fetch failed for event enrichment",
              session_id: persisted.session_id,
              reason: reason
            )

            nil
        end

      event = event_fn.(persisted, session)
      DomainEventBus.dispatch(@context, event)
      {:ok, persisted}
    end
  end

  @doc "Logs a warning on event publish failure; no-op on success."
  @spec log_publish_result(:ok | {:error, term()}, String.t()) :: :ok
  def log_publish_result(:ok, _note_id), do: :ok

  def log_publish_result({:error, reason}, note_id) do
    Logger.warning("[Participation] PubSub publish failed",
      note_id: note_id,
      reason: inspect(reason)
    )
  end
end
