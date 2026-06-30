defmodule KlassHero.Participation.Domain.Ports.ForManagingSessions do
  @moduledoc """
  Write-only port for session persistence.

  Defines the contract for session write operations (CQRS command side).
  Read operations have been moved to `ForQueryingSessions`.
  """

  alias KlassHero.Participation.ProgramSession

  @doc "Creates session. Returns `{:error, :duplicate_session}` on unique violation."
  @callback create(ProgramSession.t()) ::
              {:ok, ProgramSession.t()} | {:error, :duplicate_session | :validation_failed}

  @doc "Updates existing session. Returns `{:error, :stale_data}` on optimistic lock conflict."
  @callback update(ProgramSession.t()) ::
              {:ok, ProgramSession.t()} | {:error, :stale_data | :not_found | :validation_failed}
end
