defmodule KlassHero.Participation.Application.Commands.BulkCheckIn do
  @moduledoc """
  Use case for checking in multiple children to a session at once.

  ## Business Rules

  - All children must be registered for the session
  - All children must be in :registered status
  - Partial success is allowed (returns successful and failed records)

  ## Events Published

  - `child_checked_in` for each successful check-in
  """

  alias KlassHero.Participation.Domain.Events.ParticipationEvents
  alias KlassHero.Participation.ParticipationRecord
  alias KlassHero.Participation.ProgramSession
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

  @type params :: %{
          required(:record_ids) => [String.t()],
          required(:checked_in_by) => String.t(),
          optional(:notes) => String.t()
        }

  @type result :: %{
          successful: [ParticipationRecord.t()],
          failed: [{String.t(), term()}]
        }

  @spec execute(params()) :: result()
  def execute(%{record_ids: record_ids, checked_in_by: checked_in_by} = params) do
    notes = Map.get(params, :notes)

    # Session resolved lazily from first successful record and reused — all records share the same session_id.
    {results, _session} =
      Enum.map_reduce(record_ids, nil, fn record_id, session ->
        case check_in_record(record_id, checked_in_by, notes, session) do
          {:ok, persisted, resolved_session} ->
            {{:ok, persisted}, resolved_session}

          {:error, _, _} = error ->
            {error, session}
        end
      end)

    results
    |> Enum.reduce(%{successful: [], failed: []}, &categorize_result/2)
    |> then(fn result ->
      %{
        successful: Enum.reverse(result.successful),
        failed: Enum.reverse(result.failed)
      }
    end)
  end

  defp check_in_record(record_id, checked_in_by, notes, session) do
    with {:ok, record} <- @participation_reader.get_by_id(record_id),
         {:ok, checked_in} <- ParticipationRecord.check_in(record, checked_in_by, notes),
         {:ok, persisted} <- @participation_repository.update(checked_in) do
      session = resolve_session_best_effort(session, persisted.session_id)
      publish_event(persisted, session)
      {:ok, persisted, session}
    else
      {:error, reason} -> {:error, record_id, reason}
    end
  end

  defp resolve_session_best_effort(%ProgramSession{} = session, _session_id), do: session

  defp resolve_session_best_effort(nil, session_id) do
    case @session_reader.get_by_id(session_id) do
      {:ok, session} ->
        session

      {:error, reason} ->
        Logger.warning("[BulkCheckIn] Session fetch failed for event enrichment",
          session_id: session_id,
          reason: reason
        )

        nil
    end
  end

  defp categorize_result({:ok, record}, acc) do
    %{acc | successful: [record | acc.successful]}
  end

  defp categorize_result({:error, record_id, reason}, acc) do
    %{acc | failed: [{record_id, reason} | acc.failed]}
  end

  defp publish_event(record, %ProgramSession{} = session) do
    event = ParticipationEvents.child_checked_in(record, session)
    DomainEventBus.dispatch(@context, event)
  end

  defp publish_event(record, nil) do
    event = ParticipationEvents.child_checked_in(record)
    DomainEventBus.dispatch(@context, event)
  end
end
