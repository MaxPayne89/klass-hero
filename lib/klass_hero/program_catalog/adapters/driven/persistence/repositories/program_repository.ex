defmodule KlassHero.ProgramCatalog.Adapters.Driven.Persistence.Repositories.ProgramRepository do
  @moduledoc """
  Repository implementation for creating, listing, and updating programs.

  Implements the ForCreatingPrograms, ForListingPrograms, and ForUpdatingPrograms ports with:
  - Domain entity mapping via ProgramMapper
  - Idiomatic "let it crash" error handling

  Data integrity is enforced at the database level through NOT NULL constraints.
  Infrastructure errors (connection, query) are not caught - they crash and
  are handled by the supervision tree.
  """

  @behaviour KlassHero.ProgramCatalog.Domain.Ports.ForCreatingPrograms
  @behaviour KlassHero.ProgramCatalog.Domain.Ports.ForListingPrograms
  @behaviour KlassHero.ProgramCatalog.Domain.Ports.ForUpdatingPrograms

  use KlassHero.Shared.Tracing

  import Ecto.Query

  alias KlassHero.ProgramCatalog.Adapters.Driven.Persistence.Mappers.ProgramMapper
  alias KlassHero.ProgramCatalog.Adapters.Driven.Persistence.Queries.CursorCodec
  alias KlassHero.ProgramCatalog.Adapters.Driven.Persistence.Queries.ProgramQueries
  alias KlassHero.ProgramCatalog.Adapters.Driven.Persistence.Schemas.ProgramSchema
  alias KlassHero.ProgramCatalog.Domain.Models.Program
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.MapperHelpers
  alias KlassHero.Shared.Adapters.Driven.Persistence.RepositoryHelpers
  alias KlassHero.Shared.Domain.Types.Pagination.PageResult
  alias KlassHero.Shared.ErrorIds

  require Logger

  @doc """
  Returns a new changeset for the program creation form.

  This is an Ecto-specific concern exposed for the web layer's form rendering.
  Not part of any port — changesets are an adapter detail.
  """
  def new_changeset(attrs \\ %{}) do
    ProgramSchema.create_changeset(%ProgramSchema{}, attrs)
  end

  @impl true
  def create(%Program{} = program) do
    span do
      set_attributes("db", operation: "insert", entity: "program")

      attrs = ProgramMapper.to_schema(program)

      Logger.info("[ProgramRepository] Creating new program",
        provider_id: program.provider_id,
        title: program.title
      )

      %ProgramSchema{}
      |> ProgramSchema.create_changeset(attrs)
      |> Repo.insert()
      |> case do
        {:ok, schema} ->
          persisted = ProgramMapper.to_domain(schema)

          Logger.info("[ProgramRepository] Successfully created program",
            program_id: persisted.id,
            title: persisted.title
          )

          {:ok, persisted}

        {:error, changeset} ->
          RepositoryHelpers.log_validation_error(changeset, ErrorIds.program_create_failed())
          {:error, changeset}
      end
    end
  end

  @impl true
  @doc """
  Lists all programs from the database.

  Programs are ordered by title in ascending order for consistent display.
  Returns list of programs directly (may be empty).
  """
  def list_all_programs do
    span do
      set_attributes("db", operation: "select", entity: "program")

      Logger.info("[ProgramRepository] Starting list_all_programs query")

      programs =
        ProgramSchema
        |> order_by([p], asc: p.title)
        |> Repo.all()
        |> MapperHelpers.to_domain_list(ProgramMapper)

      Logger.info("[ProgramRepository] Successfully retrieved #{length(programs)} programs from database")

      programs
    end
  end

  @impl true
  @doc """
  Lists all programs belonging to a specific provider.

  Programs are ordered by title in ascending order for consistent display.
  Returns list of programs directly (may be empty).
  """
  def list_programs_for_provider(provider_id) when is_binary(provider_id) do
    span do
      set_attributes("db", operation: "select", entity: "program")

      Logger.info("[ProgramRepository] Starting list_programs_for_provider query for provider: #{provider_id}")

      programs =
        ProgramSchema
        |> where([p], p.provider_id == ^provider_id)
        |> order_by([p], asc: p.title)
        |> Repo.all()
        |> MapperHelpers.to_domain_list(ProgramMapper)

      Logger.info("[ProgramRepository] Successfully retrieved #{length(programs)} programs for provider #{provider_id}")

      programs
    end
  end

  @impl true
  @doc """
  Retrieves a single program by its unique ID (UUID) from the database.

  Returns:
  - `{:ok, Program.t()}` when program is found
  - `{:error, :not_found}` when no program exists with the given ID or ID is invalid
  """
  def get_by_id(id) when is_binary(id) do
    span do
      set_attributes("db", operation: "select", entity: "program")
      RepositoryHelpers.get_by_uuid(ProgramSchema, id, ProgramMapper)
    end
  end

  @impl true
  @doc """
  Lists programs with cursor-based pagination.

  Uses seek pagination (cursor-based) for efficient pagination of large result sets.
  Programs are ordered by creation time (newest first) using (inserted_at DESC, id DESC).

  Returns:
  - `{:ok, PageResult.t()}` - Page of programs with pagination metadata
  - `{:error, :invalid_cursor}` - Cursor decoding/validation failure
  """
  def list_programs_paginated(limit, cursor) do
    list_programs_paginated(limit, cursor, nil)
  end

  @impl true
  @doc """
  Lists programs with cursor-based pagination and optional category filter.

  Same as `list_programs_paginated/2` but with an additional category filter.
  Uses database-level filtering for efficient pagination with category constraints.

  Returns:
  - `{:ok, PageResult.t()}` - Page of programs with pagination metadata
  - `{:error, :invalid_cursor}` - Cursor decoding/validation failure
  """
  def list_programs_paginated(limit, cursor, category) do
    span do
      set_attributes("db", operation: "select", entity: "program")

      Logger.info(
        "[ProgramRepository] Starting list_programs_paginated query",
        limit: limit,
        has_cursor: !is_nil(cursor),
        category: category
      )

      with {:ok, validated_limit} <- validate_limit(limit),
           {:ok, cursor_data} <- CursorCodec.decode(cursor) do
        schemas = fetch_page(validated_limit, cursor_data, category)

        {items, has_more} =
          if length(schemas) > validated_limit do
            {Enum.take(schemas, validated_limit), true}
          else
            {schemas, false}
          end

        next_cursor =
          if has_more do
            items |> List.last() |> CursorCodec.encode()
          end

        domain_programs = Enum.map(items, &ProgramMapper.to_domain/1)
        page_result = PageResult.new(domain_programs, next_cursor, has_more)

        Logger.info(
          "[ProgramRepository] Successfully retrieved paginated programs",
          returned_count: length(domain_programs),
          has_more: has_more,
          category: category
        )

        {:ok, page_result}
      else
        {:error, :invalid_limit} = error ->
          Logger.warning(
            "[ProgramRepository] Invalid pagination limit",
            limit: inspect(limit)
          )

          error

        {:error, :invalid_cursor} = error ->
          Logger.warning(
            "[ProgramRepository] Invalid pagination cursor",
            error_id: ErrorIds.program_pagination_invalid_cursor(),
            cursor: cursor
          )

          error
      end
    end
  end

  @impl true
  @doc """
  Updates an existing program with optimistic locking.

  Uses the program's ID to fetch the current record from the database,
  applies the updates via an update changeset with optimistic locking,
  and returns the updated domain entity.

  Returns:
  - `{:ok, Program.t()}` - Successfully updated program
  - `{:error, :stale_data}` - Optimistic lock conflict
  - `{:error, :not_found}` - Program ID does not exist
  - `{:error, changeset}` - Validation failure
  """
  def update(%Program{} = program) do
    span do
      set_attributes("db", operation: "update", entity: "program")

      Logger.info(
        "[ProgramRepository] Starting update operation for program",
        program_id: program.id,
        title: program.title
      )

      case Repo.get(ProgramSchema, program.id) do
        nil ->
          Logger.info(
            "[ProgramRepository] Program not found during update",
            program_id: program.id
          )

          {:error, :not_found}

        current_schema ->
          do_update(current_schema, program)
      end
    end
  end

  defp do_update(current_schema, program) do
    # Trigger: lock_version nil means program was not loaded from DB
    # Why: optimistic locking requires the version the client saw at load time
    # Outcome: crash early with clear message rather than silently defaulting
    if is_nil(program.lock_version) do
      raise ArgumentError,
            "Program lock_version must not be nil — program must be loaded from the database before updating"
    end

    # Build a schema with the original lock_version from the domain model
    # This is what the client saw when they loaded the program
    schema_with_client_version = %{current_schema | lock_version: program.lock_version}

    # Convert domain Program to update attributes
    attrs = ProgramMapper.to_schema(program)

    # Build update changeset with optimistic locking
    changeset = ProgramSchema.update_changeset(schema_with_client_version, attrs)

    case Repo.update(changeset) do
      {:ok, updated_schema} ->
        updated_program = ProgramMapper.to_domain(updated_schema)

        Logger.info(
          "[ProgramRepository] Successfully updated program",
          program_id: program.id,
          title: updated_program.title,
          lock_version: updated_schema.lock_version
        )

        {:ok, updated_program}

      {:error, changeset} ->
        RepositoryHelpers.log_validation_error(changeset, ErrorIds.program_update_failed())
        {:error, changeset}
    end
  rescue
    Ecto.StaleEntryError ->
      Logger.warning(
        "[ProgramRepository] Optimistic lock conflict during program update",
        error_id: ErrorIds.program_update_stale_entry_error(),
        program_id: program.id
      )

      {:error, :stale_data}
  end

  # Private helper functions

  defp validate_limit(limit) when is_integer(limit) and limit >= 1 and limit <= 100 do
    {:ok, limit}
  end

  defp validate_limit(limit) when is_integer(limit) and limit < 1 do
    {:ok, 1}
  end

  defp validate_limit(limit) when is_integer(limit) and limit > 100 do
    {:ok, 100}
  end

  defp validate_limit(_), do: {:error, :invalid_limit}

  defp fetch_page(limit, cursor_data, category) do
    ProgramQueries.base_query()
    |> ProgramQueries.filter_by_category(category)
    |> apply_cursor_filter(cursor_data)
    |> ProgramQueries.order_by_creation(:desc)
    |> ProgramQueries.limit_results(limit + 1)
    |> Repo.all()
  end

  @impl true
  def list_ended_program_ids(cutoff_date) do
    span do
      set_attributes("db", operation: "select", entity: "program")

      ProgramSchema
      |> where([p], not is_nil(p.end_date))
      |> where([p], p.end_date < ^cutoff_date)
      |> select([p], p.id)
      |> Repo.all()
    end
  end

  @impl true
  def get_by_ids([]), do: []

  def get_by_ids(ids) when is_list(ids) do
    span do
      set_attributes("db", operation: "select", entity: "program")

      ProgramSchema
      |> where([p], p.id in ^ids)
      |> Repo.all()
      |> MapperHelpers.to_domain_list(ProgramMapper)
    end
  end

  defp apply_cursor_filter(query, nil), do: query

  defp apply_cursor_filter(query, {cursor_ts, cursor_id}) do
    ProgramQueries.paginate_after_cursor(query, {cursor_ts, cursor_id}, :desc)
  end
end
