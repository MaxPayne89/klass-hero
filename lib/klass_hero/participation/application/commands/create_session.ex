defmodule KlassHero.Participation.Application.Commands.CreateSession do
  @moduledoc """
  Use case for creating a new program session.

  ## Business Rules

  - Session must have valid time range (end after start)
  - Session cannot duplicate an existing session at the same program/date/time
  - Session starts in :scheduled status

  ## Events Published

  - `session_created` on successful creation
  """

  alias KlassHero.Participation.Domain.Events.ParticipationEvents
  alias KlassHero.Participation.ProgramSession
  alias KlassHero.Shared.DomainEventBus

  @context KlassHero.Participation

  @session_repository Application.compile_env!(:klass_hero, [:participation, :for_storing_sessions])

  @type params :: %{
          required(:program_id) => String.t(),
          required(:session_date) => Date.t(),
          required(:start_time) => Time.t(),
          required(:end_time) => Time.t(),
          optional(:location) => String.t(),
          optional(:notes) => String.t(),
          optional(:max_capacity) => pos_integer()
        }

  @type result :: {:ok, ProgramSession.t()} | {:error, term()}

  @doc """
  Creates a new program session.

  ## Parameters

  - `params` - Map containing session details

  ## Returns

  - `{:ok, session}` on success
  - `{:error, :invalid_time_range}` if end_time <= start_time
  - `{:error, :duplicate_session}` if session already exists
  - `{:error, reason}` for other failures
  """
  @spec execute(params()) :: result()
  def execute(params) when is_map(params) do
    session_attrs =
      params
      |> Map.put(:id, Ecto.UUID.generate())
      |> Map.put(:status, :scheduled)

    with {:ok, session} <- ProgramSession.new(session_attrs),
         {:ok, persisted} <- @session_repository.create(session) do
      publish_event(persisted)
      {:ok, persisted}
    end
  end

  defp publish_event(session) do
    event = ParticipationEvents.session_created(session)
    DomainEventBus.dispatch(@context, event)
  end
end
