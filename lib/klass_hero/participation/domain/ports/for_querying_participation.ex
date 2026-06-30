defmodule KlassHero.Participation.Domain.Ports.ForQueryingParticipation do
  @moduledoc """
  Read-only port for querying participation records in the Participation bounded context.

  Defines the contract for participation record read operations (CQRS query side).
  Write operations remain in `ForManagingParticipation`.
  """

  alias KlassHero.Participation.ParticipationRecord

  @doc "Retrieves participation record by ID. Returns `{:error, :not_found}` if not found."
  @callback get_by_id(binary()) :: {:ok, ParticipationRecord.t()} | {:error, :not_found}

  @doc "Lists participation records for session, ordered by child name."
  @callback list_by_session(binary()) :: [ParticipationRecord.t()]

  @doc "Lists participation records for child across all sessions."
  @callback list_by_child(binary()) :: [ParticipationRecord.t()]

  @doc "Lists participation records for child within date range."
  @callback list_by_child_and_date_range(binary(), Date.t(), Date.t()) :: [
              ParticipationRecord.t()
            ]

  @doc "Lists participation records for multiple children."
  @callback list_by_children([binary()]) :: [ParticipationRecord.t()]

  @doc "Lists participation records for multiple children within date range."
  @callback list_by_children_and_date_range([binary()], Date.t(), Date.t()) :: [
              ParticipationRecord.t()
            ]
end
