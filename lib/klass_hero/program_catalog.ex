defmodule KlassHero.ProgramCatalog do
  @moduledoc """
  Public API for the Program Catalog bounded context.

  Conventional Phoenix context: persistence and orchestration live here directly,
  calling `Repo`. Writes go to the `programs` table (`Program`); reads are served
  from the denormalised `program_listings` read model (`ProgramListing`),
  maintained by the `ProgramListings` projection. Pure display/formatting and
  category logic live in the `Domain.Services` modules.

  ## Usage

      # List all programs (read model)
      programs = ProgramCatalog.list_all_programs()

      # Get a specific program (write model, with nested value objects)
      {:ok, program} = ProgramCatalog.get_program_by_id("uuid")

      # Paginated listing with category filter
      {:ok, page} = ProgramCatalog.list_programs_paginated(20, nil, "sports")
  """

  use KlassHero.Shared.Tracing

  import Ecto.Query

  alias KlassHero.ProgramCatalog.Adapters.Driven.ACL.EnrollmentCapacityACL
  alias KlassHero.ProgramCatalog.CursorCodec
  alias KlassHero.ProgramCatalog.Domain.Events.ProgramEvents

  alias KlassHero.ProgramCatalog.Domain.Services.{
    ProgramCategories,
    ProgramFilter,
    ProgramPricing,
    TrendingSearches
  }

  alias KlassHero.ProgramCatalog.Program
  alias KlassHero.ProgramCatalog.ProgramListing
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.RepositoryHelpers
  alias KlassHero.Shared.DomainEventBus
  alias KlassHero.Shared.ErrorIds
  alias KlassHero.Shared.Pagination.PageResult

  require Logger

  @scheduling_fields ~w(meeting_days meeting_start_time meeting_end_time start_date end_date)a

  ## Writes

  @doc """
  Creates a new program.

  ## Returns

  - `{:ok, Program.t()}` on success
  - `{:error, Ecto.Changeset.t()}` on validation failure
  """
  @spec create_program(map()) :: {:ok, Program.t()} | {:error, Ecto.Changeset.t()}
  def create_program(attrs) when is_map(attrs) do
    context_span entity: "program" do
      %Program{}
      |> Program.create_changeset(attrs)
      |> Repo.insert()
      |> case do
        {:ok, program} ->
          program = Program.load_value_objects(program)
          dispatch_program_created(program)
          {:ok, program}

        {:error, changeset} ->
          RepositoryHelpers.log_validation_error(changeset, ErrorIds.program_create_failed())
          {:error, changeset}
      end
    end
  end

  @doc """
  Updates an existing program with optimistic locking.

  ## Returns

  - `{:ok, Program.t()}` on success
  - `{:error, :not_found}` if the program doesn't exist
  - `{:error, :stale_data}` if a concurrent modification was detected
  - `{:error, Ecto.Changeset.t()}` on validation failure
  """
  @spec update_program(String.t(), String.t(), map()) ::
          {:ok, Program.t()} | {:error, :not_found | :stale_data | Ecto.Changeset.t()}
  def update_program(provider_id, id, changes) when is_binary(provider_id) and is_binary(id) and is_map(changes) do
    context_span entity: "program" do
      # Ownership guard (IDOR): a program owned by another provider is
      # indistinguishable from a missing one — both return :not_found so an
      # attacker can't probe for existence by enumerating ids.
      case fetch_program(id) do
        %Program{provider_id: ^provider_id} = current ->
          do_update_program(current, changes, Program.load_value_objects(current))

        _nil_or_foreign ->
          {:error, :not_found}
      end
    end
  end

  defp do_update_program(current, attrs, original) do
    current
    |> Program.update_changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, schema} ->
        updated = Program.load_value_objects(schema)
        dispatch_program_updated(updated)
        maybe_dispatch_schedule_updated(original, updated)
        {:ok, updated}

      {:error, changeset} ->
        RepositoryHelpers.log_validation_error(changeset, ErrorIds.program_update_failed())
        {:error, changeset}
    end
  rescue
    Ecto.StaleEntryError ->
      Logger.warning("[ProgramCatalog] Optimistic lock conflict updating program",
        error_id: ErrorIds.program_update_stale_entry_error(),
        program_id: current.id
      )

      {:error, :stale_data}
  end

  ## Write-model reads

  @doc "Gets a program by ID. Returns `{:error, :not_found}` if absent or the ID is not a valid UUID."
  @spec get_program_by_id(String.t()) :: {:ok, Program.t()} | {:error, :not_found}
  def get_program_by_id(id) do
    case fetch_program(id) do
      nil -> {:error, :not_found}
      program -> {:ok, Program.load_value_objects(program)}
    end
  end

  @doc "Fetches multiple programs by ID in one query. Missing IDs are silently omitted."
  @spec get_programs_by_ids([String.t()]) :: [Program.t()]
  def get_programs_by_ids(ids) when is_list(ids) do
    Program
    |> where([p], p.id in ^ids)
    |> Repo.all()
    |> Enum.map(&Program.load_value_objects/1)
  end

  @doc "Returns IDs of programs with end_date before cutoff. Used by Messaging retention policy."
  @spec list_ended_program_ids(Date.t()) :: [String.t()]
  def list_ended_program_ids(cutoff_date) do
    Program
    |> where([p], not is_nil(p.end_date) and p.end_date < ^cutoff_date)
    |> select([p], p.id)
    |> Repo.all()
  end

  @doc "Returns the IDs of all programs owned by a provider (write model). Used by cross-context session reads."
  @spec list_program_ids_for_provider(String.t()) :: [String.t()]
  def list_program_ids_for_provider(provider_id) when is_binary(provider_id) do
    Program
    |> where([p], p.provider_id == ^provider_id)
    |> select([p], p.id)
    |> Repo.all()
  end

  @doc """
  Returns a map of `program_id => title` for the given ids (write model).

  Unknown ids are omitted from the result. Used by other contexts (e.g. the
  Messaging broadcast-summary projection) that need program titles without
  reaching into the `programs` schema.
  """
  @spec get_titles([String.t()]) :: %{String.t() => String.t()}
  def get_titles([]), do: %{}

  def get_titles(program_ids) when is_list(program_ids) do
    from(p in Program, where: p.id in ^program_ids, select: {p.id, p.title})
    |> Repo.all()
    |> Map.new()
  end

  @doc "Returns an empty changeset for the program creation form."
  @spec new_program_changeset(map()) :: Ecto.Changeset.t()
  def new_program_changeset(attrs \\ %{}) do
    Program.create_changeset(%Program{}, attrs)
  end

  ## Read-model reads (program_listings)

  @doc "Lists all available programs ordered by title."
  @spec list_all_programs() :: [ProgramListing.t()]
  def list_all_programs do
    ProgramListing
    |> order_by(asc: :title)
    |> Repo.all()
  end

  @doc "Lists featured programs for homepage display (first 2 active, ordered by title)."
  @spec list_featured_programs() :: [ProgramListing.t()]
  def list_featured_programs do
    active_listings()
    |> Enum.take(2)
  end

  @doc "Lists all programs for a provider, ordered by title (includes expired — #610)."
  @spec list_programs_for_provider(String.t()) :: [ProgramListing.t()]
  def list_programs_for_provider(provider_id) when is_binary(provider_id) do
    ProgramListing
    |> where([l], l.provider_id == ^provider_id)
    |> order_by([l], asc: l.title)
    |> Repo.all()
  end

  @doc """
  Lists programs with cursor-based pagination.

  - `limit` - maximum programs to return
  - `cursor` - cursor from a previous page (nil for the first page)
  - `category` - optional category filter (nil or "all" for all programs)
  """
  @spec list_programs_paginated(pos_integer(), String.t() | nil, String.t() | nil) ::
          {:ok, PageResult.t()} | {:error, :invalid_cursor}
  def list_programs_paginated(limit, cursor, category \\ nil) do
    category = ProgramCategories.validate_filter(category)

    with {:ok, cursor_data} <- CursorCodec.decode(cursor) do
      # Fetch limit+1 rows to detect has_more without a separate COUNT query.
      rows = listing_page(limit, cursor_data, category)

      {items, has_more} =
        if length(rows) > limit, do: {Enum.take(rows, limit), true}, else: {rows, false}

      next_cursor = if has_more, do: items |> List.last() |> CursorCodec.encode()

      {:ok, PageResult.new(items, next_cursor, has_more)}
    end
  end

  ## Pure delegations (functional core — display, filtering, categories)

  @doc "Filters programs by search query using word-boundary matching. Returns all if query is empty."
  @spec filter_programs([Program.t() | ProgramListing.t()], String.t()) :: [
          Program.t() | ProgramListing.t()
        ]
  defdelegate filter_programs(programs, query), to: ProgramFilter, as: :execute

  @doc "Trims and length-limits a search query. Returns empty string for nil."
  @spec sanitize_query(String.t() | nil) :: String.t()
  defdelegate sanitize_query(query), to: ProgramFilter

  @doc "Returns all valid category identifiers including \"all\"."
  @spec valid_categories() :: [String.t()]
  defdelegate valid_categories, to: ProgramCategories

  @doc "Returns valid program categories (excludes \"all\")."
  @spec program_categories() :: [String.t()]
  defdelegate program_categories, to: ProgramCategories

  @doc "Validates a category filter, returning \"all\" for invalid values."
  @spec validate_category_filter(String.t() | nil) :: String.t()
  defdelegate validate_category_filter(filter), to: ProgramCategories, as: :validate_filter

  @doc "Returns true if category is valid for program assignment (excludes \"all\")."
  @spec valid_program_category?(String.t()) :: boolean()
  defdelegate valid_program_category?(category), to: ProgramCategories

  @doc "Formats a price for display with currency symbol (e.g. \"€45.00\")."
  @spec format_price(Decimal.t() | number() | nil) :: String.t()
  defdelegate format_price(price), to: ProgramPricing

  @doc "Checks if the program's registration is currently open."
  @spec registration_open?(Program.t()) :: boolean()
  defdelegate registration_open?(program), to: Program

  @doc "Returns the current registration status of the program."
  @spec registration_status(Program.t()) :: atom()
  defdelegate registration_status(program), to: Program

  @doc "Returns trending search terms, optionally limited to `limit` entries."
  @spec trending_searches(pos_integer() | nil) :: [String.t()]
  def trending_searches(limit \\ nil)
  def trending_searches(nil), do: TrendingSearches.list()
  def trending_searches(limit), do: TrendingSearches.list(limit)

  @doc "Returns remaining enrollment capacity for a program via Enrollment ACL."
  defdelegate remaining_capacity(program_id), to: EnrollmentCapacityACL

  @doc "Returns a map of `program_id => remaining_count | :unlimited` for multiple programs."
  defdelegate remaining_capacities(program_ids), to: EnrollmentCapacityACL

  ## Internals

  defp fetch_program(id) when is_binary(id) do
    # dump/1 validates UUID format; cast/1 wrongly accepts any 16-byte binary.
    case Ecto.UUID.dump(id) do
      {:ok, _binary} -> Repo.get(Program, id)
      :error -> nil
    end
  end

  defp fetch_program(_), do: nil

  defp active_listings do
    today = Date.utc_today()

    ProgramListing
    |> where([l], is_nil(l.end_date) or l.end_date >= ^today)
    |> order_by([l], asc: l.title)
    |> Repo.all()
  end

  defp listing_page(limit, cursor_data, category) do
    ProgramListing
    |> filter_listing_category(category)
    |> where([l], is_nil(l.end_date) or l.end_date >= ^Date.utc_today())
    |> filter_listing_cursor(cursor_data)
    |> order_by([l], desc: l.inserted_at, desc: l.id)
    |> limit(^(limit + 1))
    |> Repo.all()
  end

  defp filter_listing_category(query, nil), do: query
  defp filter_listing_category(query, "all"), do: query

  defp filter_listing_category(query, category) when is_binary(category) do
    where(query, [l], l.category == ^category)
  end

  defp filter_listing_cursor(query, nil), do: query

  defp filter_listing_cursor(query, {cursor_ts, cursor_id}) do
    # Seek pagination: skip rows at or before the cursor in (inserted_at DESC, id DESC) order.
    where(
      query,
      [l],
      l.inserted_at < ^cursor_ts or
        (l.inserted_at == ^cursor_ts and l.id < ^cursor_id)
    )
  end

  defp dispatch_program_created(program) do
    program.id
    |> ProgramEvents.program_created(%{
      provider_id: program.provider_id,
      title: program.title,
      category: program.category,
      meeting_days: program.meeting_days,
      meeting_start_time: program.meeting_start_time,
      meeting_end_time: program.meeting_end_time,
      start_date: program.start_date,
      end_date: program.end_date
    })
    |> dispatch("program_created", program.id)
  end

  defp dispatch_program_updated(program) do
    program.id
    |> ProgramEvents.program_updated(%{
      provider_id: program.provider_id,
      title: program.title,
      description: program.description,
      category: program.category,
      age_range: program.age_range,
      price: program.price,
      pricing_period: program.pricing_period,
      location: program.location,
      cover_image_url: program.cover_image_url,
      start_date: program.start_date,
      end_date: program.end_date,
      meeting_days: program.meeting_days,
      meeting_start_time: program.meeting_start_time,
      meeting_end_time: program.meeting_end_time,
      registration_start_date: program.registration_start_date,
      registration_end_date: program.registration_end_date
    })
    |> dispatch("program_updated", program.id)
  end

  defp maybe_dispatch_schedule_updated(original, updated) do
    changed? =
      Enum.any?(@scheduling_fields, fn field ->
        Map.get(original, field) != Map.get(updated, field)
      end)

    if changed? do
      updated.id
      |> ProgramEvents.program_schedule_updated(%{
        provider_id: updated.provider_id,
        meeting_days: updated.meeting_days,
        meeting_start_time: updated.meeting_start_time,
        meeting_end_time: updated.meeting_end_time,
        start_date: updated.start_date,
        end_date: updated.end_date
      })
      |> dispatch("program_schedule_updated", updated.id)
    end
  end

  # Fire-and-forget: dispatch failures are logged but never roll back the write.
  defp dispatch(event, name, program_id) do
    case DomainEventBus.dispatch(KlassHero.ProgramCatalog, event) do
      :ok ->
        :ok

      {:error, failures} ->
        Logger.error("[ProgramCatalog] #{name} event dispatch had failures",
          program_id: program_id,
          errors: inspect(failures)
        )
    end
  end
end
