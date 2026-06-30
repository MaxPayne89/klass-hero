defmodule KlassHero.Participation.Application.Commands.StartSession do
  @moduledoc """
  Use case for starting a scheduled session.

  ## Business Rules

  - Only :scheduled sessions can be started
  - Session transitions to :in_progress status

  ## Events Published

  - `session_started` on successful start
  """

  alias KlassHero.Participation.Domain.Events.ParticipationEvents
  alias KlassHero.Participation.ProgramSession
  alias KlassHero.Shared.DomainEventBus

  @context KlassHero.Participation

  @session_reader Application.compile_env!(:klass_hero, [:participation, :for_querying_sessions])
  @session_repository Application.compile_env!(:klass_hero, [:participation, :for_storing_sessions])

  @type result :: {:ok, ProgramSession.t()} | {:error, term()}

  @doc """
  Starts a scheduled session.

  ## Parameters

  - `session_id` - ID of the session to start

  ## Returns

  - `{:ok, session}` on success
  - `{:error, :not_found}` if session doesn't exist
  - `{:error, :invalid_status_transition}` if not in :scheduled status
  - `{:error, :stale_data}` on concurrent modification
  """
  @spec execute(String.t()) :: result()
  def execute(session_id) when is_binary(session_id) do
    with {:ok, session} <- @session_reader.get_by_id(session_id),
         {:ok, started} <- ProgramSession.start(session),
         {:ok, persisted} <- @session_repository.update(started) do
      publish_event(persisted)
      {:ok, persisted}
    end
  end

  defp publish_event(session) do
    event = ParticipationEvents.session_started(session)
    DomainEventBus.dispatch(@context, event)
  end
end
