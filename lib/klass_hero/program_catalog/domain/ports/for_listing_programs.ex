defmodule KlassHero.ProgramCatalog.Domain.Ports.ForListingPrograms do
  @moduledoc """
  Repository port for listing programs in the Program Catalog bounded context.

  This is a behaviour (interface) that defines the contract for program persistence.
  It is implemented by adapters in the infrastructure layer (e.g., Ecto repositories).

  This port follows the Ports & Adapters architecture pattern, keeping the domain
  layer independent of infrastructure concerns.

  ## Expected Return Values

  - `list_all_programs/0` - Returns list of Program structs
  - `get_by_id/1` - Returns `{:ok, Program.t()}` or `{:error, :not_found}`
  - `list_programs_paginated/2` - Returns `{:ok, PageResult}` or `{:error, :invalid_cursor}`

  Infrastructure errors (connection, query) are not caught - they crash and
  are handled by the supervision tree.
  """

  alias KlassHero.ProgramCatalog.Domain.Models.Program
  alias KlassHero.Shared.Domain.Types.Pagination.PageResult

  @doc """
  Lists all valid programs from the repository.

  Only programs with all required fields populated are returned.
  Programs are returned in ascending order by title.

  Returns a list of Program structs (may be empty).
  """
  @callback list_all_programs() :: [Program.t()]

  @doc """
  Retrieves a single program by its unique ID (UUID).

  Returns:
  - `{:ok, Program.t()}` - Program found with matching ID
  - `{:error, :not_found}` - No program exists with the given ID
  """
  @callback get_by_id(id :: binary()) :: {:ok, Program.t()} | {:error, :not_found}

  @doc """
  Lists programs with cursor-based pagination.

  Uses seek pagination with a cursor-based approach for efficient pagination
  of large result sets. The cursor encodes the position in the result set
  and should be treated as an opaque string.

  Programs are returned in descending order by creation time (newest first).

  Parameters:
  - `limit` - Number of items per page (1-100)
  - `cursor` - Base64-encoded cursor for pagination, nil for first page

  Returns:
  - `{:ok, PageResult}` - Page of programs with pagination metadata
  - `{:error, :invalid_cursor}` - Cursor decoding/validation failure
  """
  @callback list_programs_paginated(limit :: pos_integer(), cursor :: binary() | nil) ::
              {:ok, %PageResult{}} | {:error, :invalid_cursor}

  @doc """
  Lists programs with cursor-based pagination and optional category filter.

  Same as `list_programs_paginated/2` but with an additional category filter.
  Uses database-level filtering for efficient pagination with category constraints.

  Parameters:
  - `limit` - Number of items per page (1-100)
  - `cursor` - Base64-encoded cursor for pagination, nil for first page
  - `category` - Category to filter by, or nil/"all" for all categories

  Returns:
  - `{:ok, PageResult}` - Page of programs with pagination metadata
  - `{:error, :invalid_cursor}` - Cursor decoding/validation failure
  """
  @callback list_programs_paginated(
              limit :: pos_integer(),
              cursor :: binary() | nil,
              category :: String.t() | nil
            ) ::
              {:ok, %PageResult{}} | {:error, :invalid_cursor}

  @doc """
  Lists all programs belonging to a specific provider.

  Programs are returned in ascending order by title for consistent display.
  Returns a list of Program structs (may be empty if provider has no programs).
  """
  @callback list_programs_for_provider(provider_id :: String.t()) :: [Program.t()]

  @doc """
  Returns IDs of programs whose end_date is before the given cutoff date.

  Only programs with a non-nil end_date that falls before cutoff_date
  are included. Used by the Messaging context for retention policy
  (archiving broadcast conversations for ended programs).
  """
  @callback list_ended_program_ids(cutoff_date :: Date.t()) :: [String.t()]

  @doc """
  Returns all programs matching the given list of IDs in a single query.

  IDs that do not correspond to any program are silently omitted from the result.
  The order of returned programs is not guaranteed.
  """
  @callback get_by_ids(ids :: [String.t()]) :: [Program.t()]
end
