defmodule KlassHero.Participation.Adapters.Driven.ACL.ProgramProviderResolver do
  @moduledoc """
  Adapter for resolving program ownership from ProgramCatalog context.

  ## Anti-Corruption Layer

  This adapter serves as an anti-corruption layer between the Participation and
  ProgramCatalog bounded contexts. It resolves which provider owns a given program.

  A cross-context read calls the owning facade directly by default (ADR 0015); this
  adapter earns its place by the error mapping below, not by the indirection.

  ```
  NotifyLiveViews Handler → [THIS ADAPTER] → ProgramCatalog Public API
       (needs provider_id)    (ACL lookup)     (owns Program model)
  ```

  ## Error Mapping

  ProgramCatalog errors are mapped to Participation semantics:
  - Empty result from `get_programs_by_ids/1` → `:program_not_found`
  """

  alias KlassHero.ProgramCatalog

  require Logger

  def resolve_provider_id(program_id) when is_binary(program_id) do
    with {:ok, program} <- fetch_program(program_id), do: {:ok, program.provider_id}
  end

  def resolve_provider_details(program_id) when is_binary(program_id) do
    with {:ok, program} <- fetch_program(program_id) do
      {:ok, %{provider_id: program.provider_id, program_title: program.title}}
    end
  end

  defp fetch_program(program_id) do
    case ProgramCatalog.get_programs_by_ids([program_id]) do
      [program] -> {:ok, program}
      _other -> {:error, :program_not_found}
    end
  rescue
    error ->
      Logger.warning("[ProgramProviderResolver] Failed to fetch program",
        program_id: program_id,
        error: Exception.message(error)
      )

      {:error, :program_not_found}
  end
end
