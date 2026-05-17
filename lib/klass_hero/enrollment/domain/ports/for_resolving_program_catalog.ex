defmodule KlassHero.Enrollment.Domain.Ports.ForResolvingProgramCatalog do
  @moduledoc """
  Port for resolving program catalog data from the Enrollment context.

  Provides a cross-context lookup without directly depending on the
  ProgramCatalog bounded context (which would create a dependency cycle).
  """

  @doc """
  Returns a map of program titles to program IDs for a given provider.

  Used during CSV import to resolve program names to database IDs.

  Returns `%{"Program Title" => "program-uuid", ...}`.
  """
  @callback list_program_titles_for_provider(binary()) :: %{String.t() => binary()}

  @doc """
  Returns true if the given program is owned by the given provider.

  Returns false for unknown programs and for programs owned by other providers.
  """
  @callback program_owned_by?(program_id :: binary(), provider_id :: binary()) :: boolean()
end
