defmodule KlassHero.ProgramCatalog.Adapters.Driven.Persistence.Repositories.ProgramListingsRepository do
  @moduledoc """
  Read-side repository for the program_listings denormalized table.

  Implements the ForListingProgramSummaries port. This repository only reads —
  the projection GenServer handles all writes to the program_listings table.

  Returns lightweight ProgramListing DTOs (no domain entities, no value objects).
  Uses cursor-based pagination matching the write-side ProgramRepository pattern.
  """

  @behaviour KlassHero.ProgramCatalog.Domain.Ports.ForListingProgramSummaries

  use KlassHero.Shared.Interaction

  import Ecto.Query

  alias KlassHero.ProgramCatalog.Adapters.Driven.Persistence.Queries.CursorCodec
  alias KlassHero.ProgramCatalog.Adapters.Driven.Persistence.Schemas.ProgramListingSchema
  alias KlassHero.ProgramCatalog.Domain.ReadModels.ProgramListing
  alias KlassHero.Repo
  alias KlassHero.Shared.Domain.Types.Pagination.PageResult

  require Logger

  @impl true
  def list_paginated(limit, cursor, category) do
    db_interaction operation: :list_paginated, entity: "program_listing" do
      Logger.debug("[ProgramListingsRepository] Listing paginated program listings",
        limit: limit,
        has_cursor: !is_nil(cursor),
        category: category
      )

      with {:ok, cursor_data} <- CursorCodec.decode(cursor) do
        schemas = fetch_page(limit, cursor_data, category)

        # Fetched limit+1 rows to detect has_more without a separate COUNT query.
        {items, has_more} =
          if length(schemas) > limit do
            {Enum.take(schemas, limit), true}
          else
            {schemas, false}
          end

        next_cursor =
          if has_more do
            items |> List.last() |> CursorCodec.encode()
          end

        dtos = Enum.map(items, &to_dto/1)
        page_result = PageResult.new(dtos, next_cursor, has_more)

        Logger.debug("[ProgramListingsRepository] Retrieved paginated listings",
          returned_count: length(dtos),
          has_more: has_more
        )

        {:ok, page_result}
      end
    end
  end

  @impl true
  def list_all do
    db_interaction operation: :list_all, entity: "program_listing" do
      Logger.debug("[ProgramListingsRepository] Listing all program listings")

      schemas =
        ProgramListingSchema
        |> order_by(asc: :title)
        |> Repo.all()

      dtos = Enum.map(schemas, &to_dto/1)

      Logger.debug("[ProgramListingsRepository] Retrieved all listings",
        count: length(dtos)
      )

      dtos
    end
  end

  @impl true
  def list_active do
    db_interaction operation: :list_active, entity: "program_listing" do
      Logger.debug("[ProgramListingsRepository] Listing active program listings")

      schemas =
        ProgramListingSchema
        |> apply_end_date_filter()
        |> order_by(asc: :title)
        |> Repo.all()

      dtos = Enum.map(schemas, &to_dto/1)

      Logger.debug("[ProgramListingsRepository] Retrieved active listings",
        count: length(dtos)
      )

      dtos
    end
  end

  @impl true
  def list_for_provider(provider_id) when is_binary(provider_id) do
    db_interaction operation: :list_for_provider, entity: "program_listing" do
      Logger.debug("[ProgramListingsRepository] Listing programs for provider",
        provider_id: provider_id
      )

      schemas =
        ProgramListingSchema
        |> where([l], l.provider_id == ^provider_id)
        |> order_by([l], asc: l.title)
        |> Repo.all()

      dtos = Enum.map(schemas, &to_dto/1)

      Logger.debug("[ProgramListingsRepository] Retrieved provider listings",
        provider_id: provider_id,
        count: length(dtos)
      )

      dtos
    end
  end

  @impl true
  def get_by_id(id) when is_binary(id) do
    db_interaction operation: :get_by_id, entity: "program_listing" do
      # dump/1 validates UUID format; cast/1 incorrectly accepts 16-byte binaries.
      case Ecto.UUID.dump(id) do
        {:ok, _binary} ->
          case Repo.get(ProgramListingSchema, id) do
            nil ->
              Logger.debug("[ProgramListingsRepository] Listing not found", entity_id: id)
              {:error, :not_found}

            schema ->
              {:ok, to_dto(schema)}
          end

        :error ->
          Logger.debug("[ProgramListingsRepository] Invalid UUID format", entity_id: id)
          {:error, :not_found}
      end
    end
  end

  defp fetch_page(limit, cursor_data, category) do
    ProgramListingSchema
    |> apply_category_filter(category)
    |> apply_end_date_filter()
    |> apply_cursor_filter(cursor_data)
    |> order_by([l], desc: l.inserted_at, desc: l.id)
    |> limit(^(limit + 1))
    |> Repo.all()
  end

  defp apply_category_filter(query, nil), do: query
  defp apply_category_filter(query, "all"), do: query

  defp apply_category_filter(query, category) when is_binary(category) do
    where(query, [l], l.category == ^category)
  end

  # Public-facing surfaces only (fetch_page, list_active). list_all/0 and list_for_provider/1
  # intentionally bypass this so provider/admin tooling still surfaces expired programs (#610).
  defp apply_end_date_filter(query) do
    today = Date.utc_today()
    where(query, [l], is_nil(l.end_date) or l.end_date >= ^today)
  end

  defp apply_cursor_filter(query, nil), do: query

  defp apply_cursor_filter(query, {cursor_ts, cursor_id}) do
    # Seek pagination: skip rows at or before the cursor in (inserted_at DESC, id DESC) order.
    where(
      query,
      [l],
      l.inserted_at < ^cursor_ts or
        (l.inserted_at == ^cursor_ts and l.id < ^cursor_id)
    )
  end

  defp to_dto(%ProgramListingSchema{} = schema) do
    ProgramListing.new(%{
      id: schema.id,
      title: schema.title,
      description: schema.description,
      category: schema.category,
      age_range: schema.age_range,
      price: schema.price,
      pricing_period: schema.pricing_period,
      location: schema.location,
      cover_image_url: schema.cover_image_url,
      instructor_name: schema.instructor_name,
      instructor_headshot_url: schema.instructor_headshot_url,
      start_date: schema.start_date,
      end_date: schema.end_date,
      meeting_days: schema.meeting_days,
      meeting_start_time: schema.meeting_start_time,
      meeting_end_time: schema.meeting_end_time,
      season: schema.season,
      registration_start_date: schema.registration_start_date,
      registration_end_date: schema.registration_end_date,
      provider_id: schema.provider_id,
      provider_verified: schema.provider_verified,
      inserted_at: schema.inserted_at,
      updated_at: schema.updated_at
    })
  end
end
