defmodule KlassHero.ProgramCatalog do
  @moduledoc """
  Public API for the Program Catalog bounded context.

  This facade provides a clean interface to the Program Catalog domain,
  hiding internal architecture details (use cases, services, repositories)
  from external consumers like LiveViews and controllers.

  ## Usage

      # List all programs
      programs = ProgramCatalog.list_all_programs()

      # Get a specific program
      {:ok, program} = ProgramCatalog.get_program_by_id("uuid")

      # List featured programs for homepage
      featured = ProgramCatalog.list_featured_programs()

      # Paginated listing with category filter
      {:ok, page} = ProgramCatalog.list_programs_paginated(20, nil, "sports")

      # Filter programs by search query
      filtered = ProgramCatalog.filter_programs(programs, "art")

      # Validate and format categories
      category = ProgramCatalog.validate_category_filter("sports")
      true = ProgramCatalog.valid_program_category?("sports")

      # Format prices
      "€45.00" = ProgramCatalog.format_price(Decimal.new("45.00"))

  """

  use Boundary,
    top_level?: true,
    deps: [KlassHero, KlassHero.Provider, KlassHero.Shared, KlassHero.Enrollment],
    exports: [
      Domain.Models.Instructor,
      Domain.Models.Program,
      Domain.ReadModels.ProgramListing,
      Domain.Services.ProgramCategories
    ]

  alias KlassHero.ProgramCatalog.Adapters.Driven.ACL.EnrollmentCapacityACL

  alias KlassHero.ProgramCatalog.Application.Commands.{
    CreateProgram,
    UpdateProgram
  }

  alias KlassHero.ProgramCatalog.Application.Queries.{
    GetProgramById,
    ListAllPrograms,
    ListFeaturedPrograms,
    ListProgramsPaginated,
    ListProviderPrograms,
    ProgramCatalogQueries
  }

  alias KlassHero.ProgramCatalog.Domain.Models.Program
  alias KlassHero.ProgramCatalog.Domain.ReadModels.ProgramListing

  alias KlassHero.ProgramCatalog.Domain.Services.{
    ProgramCategories,
    ProgramFilter,
    ProgramPricing,
    TrendingSearches
  }

  # ===========================================================================
  # Commands
  # ===========================================================================

  @doc """
  Creates a new program.

  ## Parameters

  - `attrs` - Map with: title, description, category, price, provider_id.
    Optional: location, cover_image_url, instructor_id, instructor_name, instructor_headshot_url.
  - `tier_holder` - Provider domain model (must have `:subscription_tier` field).
    Used to check program creation entitlement.

  ## Returns

  - `{:ok, Program.t()}` on success
  - `{:error, :program_limit_reached}` if provider has reached their tier's program limit
  - `{:error, changeset}` on validation failure
  """
  @spec create_program(map(), map()) :: {:ok, Program.t()} | {:error, term()}
  def create_program(attrs, tier_holder) when is_map(attrs) do
    CreateProgram.execute(attrs, tier_holder)
  end

  @doc """
  Updates an existing program.

  Loads the current program, applies changes through the domain model,
  and persists with optimistic locking.

  ## Parameters

  - `id` - Program UUID
  - `changes` - Map of fields to update

  ## Returns

  - `{:ok, Program.t()}` on success
  - `{:error, :not_found}` if program doesn't exist
  - `{:error, :stale_data}` if concurrent modification detected
  - `{:error, errors}` on validation failure
  """
  @spec update_program(String.t(), map()) :: {:ok, Program.t()} | {:error, term()}
  def update_program(id, changes) when is_binary(id) and is_map(changes) do
    UpdateProgram.execute(id, changes)
  end

  # ===========================================================================
  # Queries
  # ===========================================================================

  @doc """
  Lists all available programs.

  Returns programs ordered by title.

  ## Examples

      programs = ProgramCatalog.list_all_programs()
  """
  @spec list_all_programs() :: [ProgramListing.t()]
  defdelegate list_all_programs, to: ListAllPrograms, as: :execute

  @doc """
  Gets a program by its unique ID.

  ## Examples

      {:ok, program} = ProgramCatalog.get_program_by_id("uuid")
      {:error, :not_found} = ProgramCatalog.get_program_by_id("invalid")
  """
  @spec get_program_by_id(String.t()) :: {:ok, Program.t()} | {:error, atom()}
  defdelegate get_program_by_id(id), to: GetProgramById, as: :execute

  @doc """
  Lists featured programs for homepage display.

  Returns the first 2 programs ordered by title.

  ## Examples

      featured = ProgramCatalog.list_featured_programs()
  """
  @spec list_featured_programs() :: [ProgramListing.t()]
  defdelegate list_featured_programs, to: ListFeaturedPrograms, as: :execute

  @doc """
  Lists programs with cursor-based pagination.

  ## Parameters

    * `limit` - Maximum number of programs to return (1-100)
    * `cursor` - Optional cursor from previous page (nil for first page)
    * `category` - Optional category filter (nil or "all" for all programs)

  ## Examples

      {:ok, page} = ProgramCatalog.list_programs_paginated(20, nil)
      {:ok, next_page} = ProgramCatalog.list_programs_paginated(20, page.next_cursor, "sports")
  """
  @spec list_programs_paginated(pos_integer(), String.t() | nil, String.t() | nil) ::
          {:ok, map()} | {:error, :invalid_cursor}
  def list_programs_paginated(limit, cursor, category \\ nil) do
    ListProgramsPaginated.execute(limit, cursor, category)
  end

  @doc """
  Lists all programs belonging to a specific provider.

  Returns programs ordered by title for consistent display.

  ## Examples

      programs = ProgramCatalog.list_programs_for_provider(provider_id)
  """
  @spec list_programs_for_provider(String.t()) :: [ProgramListing.t()]
  defdelegate list_programs_for_provider(provider_id), to: ListProviderPrograms, as: :execute

  @doc """
  Filters programs by search query using word-boundary matching.

  Returns all programs if query is empty.

  ## Examples

      filtered = ProgramCatalog.filter_programs(programs, "art")
  """
  @spec filter_programs([Program.t() | ProgramListing.t()], String.t()) :: [
          Program.t() | ProgramListing.t()
        ]
  defdelegate filter_programs(programs, query), to: ProgramFilter, as: :execute

  @doc """
  Sanitizes a search query by trimming and limiting length.

  ## Examples

      "art" = ProgramCatalog.sanitize_query("  art  ")
      "" = ProgramCatalog.sanitize_query(nil)
  """
  @spec sanitize_query(String.t() | nil) :: String.t()
  defdelegate sanitize_query(query), to: ProgramFilter

  @doc """
  Returns all valid category identifiers including "all".

  ## Examples

      ["all", "sports", "arts", ...] = ProgramCatalog.valid_categories()
  """
  @spec valid_categories() :: [String.t()]
  defdelegate valid_categories, to: ProgramCategories

  @doc """
  Returns valid categories for programs (excludes "all").

  ## Examples

      ["sports", "arts", ...] = ProgramCatalog.program_categories()
  """
  @spec program_categories() :: [String.t()]
  defdelegate program_categories, to: ProgramCategories

  @doc """
  Validates a category filter, returning "all" for invalid values.

  ## Examples

      "sports" = ProgramCatalog.validate_category_filter("sports")
      "all" = ProgramCatalog.validate_category_filter("invalid")
  """
  @spec validate_category_filter(String.t() | nil) :: String.t()
  defdelegate validate_category_filter(filter), to: ProgramCategories, as: :validate_filter

  @doc """
  Checks if a category is valid for assignment to a program.

  Excludes "all" which is only valid as a filter.

  ## Examples

      true = ProgramCatalog.valid_program_category?("sports")
      false = ProgramCatalog.valid_program_category?("all")
  """
  @spec valid_program_category?(String.t()) :: boolean()
  defdelegate valid_program_category?(category), to: ProgramCategories

  @doc """
  Formats a price for display with currency symbol.

  ## Examples

      "€45.00" = ProgramCatalog.format_price(Decimal.new("45.00"))
  """
  @spec format_price(Decimal.t() | number() | nil) :: String.t()
  defdelegate format_price(price), to: ProgramPricing

  @doc """
  Checks if the program's registration is currently open.
  """
  @spec registration_open?(Program.t()) :: boolean()
  defdelegate registration_open?(program), to: Program

  @doc """
  Returns the current registration status of the program.
  """
  @spec registration_status(Program.t()) :: atom()
  defdelegate registration_status(program), to: Program

  @doc """
  Returns trending search terms.

  ## Examples

      tags = ProgramCatalog.trending_searches()
      tags = ProgramCatalog.trending_searches(3)  # limited to 3
  """
  @spec trending_searches(pos_integer() | nil) :: [String.t()]
  def trending_searches(limit \\ nil)
  def trending_searches(nil), do: TrendingSearches.list()
  def trending_searches(limit), do: TrendingSearches.list(limit)

  @doc """
  Counts self-posted programs for a provider.

  Used by the provider dashboard to display accurate program slot usage.
  Only programs with `origin: :self_posted` are counted — business-assigned
  programs do not count toward the tier limit.
  """
  @spec count_self_posted_programs(String.t()) :: non_neg_integer()
  def count_self_posted_programs(provider_id) do
    ProgramCatalogQueries.count_self_posted_programs(provider_id)
  end

  @doc """
  Returns IDs of programs whose end_date is before the given cutoff date.

  Used by the Messaging context's retention policy to archive broadcast
  conversations for ended programs.
  """
  @spec list_ended_program_ids(Date.t()) :: [String.t()]
  def list_ended_program_ids(cutoff_date) do
    ProgramCatalogQueries.list_ended_program_ids(cutoff_date)
  end

  @doc """
  Fetches multiple programs by a list of IDs in a single database query.

  Returns a list of Program structs for all matching IDs. IDs with no corresponding
  program are silently omitted. Use this instead of calling `get_program_by_id/1`
  in a loop to avoid N+1 queries.

  ## Examples

      programs = ProgramCatalog.get_programs_by_ids(["uuid1", "uuid2"])
  """
  @spec get_programs_by_ids([String.t()]) :: [Program.t()]
  def get_programs_by_ids(ids) when is_list(ids) do
    ProgramCatalogQueries.get_programs_by_ids(ids)
  end

  @doc """
  Returns remaining enrollment capacity for a program via ACL.
  Delegates to the Enrollment context.
  """
  defdelegate remaining_capacity(program_id),
    to: EnrollmentCapacityACL

  @doc """
  Returns remaining enrollment capacity for multiple programs via ACL.
  Returns a map of `program_id => remaining_count | :unlimited`.
  """
  defdelegate remaining_capacities(program_ids),
    to: EnrollmentCapacityACL

  # ===========================================================================
  # Forms
  # ===========================================================================

  @doc """
  Returns an empty changeset for the program creation form.
  """
  def new_program_changeset(attrs \\ %{}) do
    ProgramCatalogQueries.new_program_changeset(attrs)
  end
end
