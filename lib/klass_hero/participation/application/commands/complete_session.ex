defmodule KlassHero.Participation.Application.Commands.CompleteSession do
  @moduledoc """
  Use case for completing an in-progress session.

  ## Business Rules

  - Only :in_progress sessions can be completed
  - Session transitions to :completed status
  - Remaining :registered participants are marked as :absent

  ## Events Published

  - `session_completed` on successful completion
  - `child_marked_absent` for each child marked absent
  """

  alias KlassHero.Participation.Domain.Events.ParticipationEvents
  alias KlassHero.Participation.ProgramSession
  alias KlassHero.Shared.DomainEventBus

  require Logger

  @context KlassHero.Participation

  @session_reader Application.compile_env!(:klass_hero, [:participation, :for_querying_sessions])
  @session_repository Application.compile_env!(:klass_hero, [:participation, :for_storing_sessions])
  @participation_reader Application.compile_env!(:klass_hero, [
                          :participation,
                          :for_querying_participation_records
                        ])
  @participation_repository Application.compile_env!(:klass_hero, [
                              :participation,
                              :for_storing_participation_records
                            ])
  @program_provider_resolver Application.compile_env!(:klass_hero, [
                               :participation,
                               :for_resolving_program_provider
                             ])

  @type result :: {:ok, ProgramSession.t()} | {:error, term()}

  @doc """
  Completes an in-progress session.

  Marks all registered (not checked in) children as absent.

  ## Parameters

  - `session_id` - ID of the session to complete

  ## Returns

  - `{:ok, session}` on success
  - `{:error, :not_found}` if session doesn't exist
  - `{:error, :invalid_status_transition}` if not in :in_progress status
  """
  @spec execute(String.t()) :: result()
  def execute(session_id) when is_binary(session_id) do
    with {:ok, session} <- @session_reader.get_by_id(session_id),
         {:ok, completed} <- ProgramSession.complete(session),
         {:ok, persisted} <- @session_repository.update(completed),
         :ok <- mark_remaining_as_absent(persisted) do
      publish_session_completed(persisted)
      {:ok, persisted}
    end
  end

  defp mark_remaining_as_absent(session) do
    registered =
      session.id
      |> @participation_reader.list_by_session()
      |> Enum.filter(&(&1.status == :registered))

    ids = Enum.map(registered, & &1.id)

    {:ok, _count} = @participation_repository.mark_absent_batch(ids)

    Enum.each(registered, fn record ->
      publish_child_absent(%{record | status: :absent}, session)
    end)

    :ok
  end

  defp publish_session_completed(session) do
    extra_payload = resolve_provider_details(session.program_id)
    event = ParticipationEvents.session_completed(session, extra_payload: extra_payload)
    DomainEventBus.dispatch(@context, event)
  end

  defp resolve_provider_details(program_id) do
    case @program_provider_resolver.resolve_provider_details(program_id) do
      {:ok, details} ->
        details

      {:error, reason} ->
        Logger.warning("Could not resolve provider details for session_completed event",
          program_id: program_id,
          reason: inspect(reason)
        )

        %{provider_id: "00000000-0000-0000-0000-000000000000", program_title: "Unknown Program"}
    end
  end

  defp publish_child_absent(record, session) do
    event = ParticipationEvents.child_marked_absent(record, session)
    DomainEventBus.dispatch(@context, event)
  end
end
