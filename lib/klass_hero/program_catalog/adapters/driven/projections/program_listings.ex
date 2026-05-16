defmodule KlassHero.ProgramCatalog.Adapters.Driven.Projections.ProgramListings do
  @moduledoc """
  Event-driven projection maintaining the `program_listings` read table.

  Mirrors program data + provider verification status from write tables so
  Program Catalog queries can serve denormalised reads without joins.

  Built on `KlassHero.Shared.Projection` (base) + `Projection.WithBootstrapRetry`
  (linear-backoff retry on transient bootstrap failure).

  ## Event handling

  - `:program_created` — inserts a new listing row
  - `:program_updated` — updates listing fields (preserves season + provider_verified)
  - `:provider_verified` — bulk sets `provider_verified = true` for the provider's listings
  - `:provider_unverified` — bulk sets `provider_verified = false`

  Bang functions (`Repo.insert!`, `Repo.update!`) are used intentionally — if a
  DB write fails, the GenServer crashes and the supervisor restarts it, triggering
  a full re-bootstrap. Transient failures resolve via restart; persistent failures
  surface as repeated crashes (hitting `max_restarts`).
  """

  use KlassHero.Shared.Projection,
    topics: [
      "integration:program_catalog:program_created",
      "integration:program_catalog:program_updated",
      "integration:provider:provider_verified",
      "integration:provider:provider_unverified"
    ]

  use KlassHero.Shared.Projection.WithBootstrapRetry

  import Ecto.Query

  alias KlassHero.ProgramCatalog.Adapters.Driven.Persistence.Schemas.ProgramListingSchema
  alias KlassHero.ProgramCatalog.Adapters.Driven.Persistence.Schemas.ProgramSchema
  alias KlassHero.ProgramCatalog.Adapters.Driven.Projections.VerifiedProviders
  alias KlassHero.Repo
  alias KlassHero.Shared.Projection

  # Fields shared between ProgramSchema and ProgramListingSchema
  @shared_fields [
    :title,
    :description,
    :category,
    :age_range,
    :price,
    :pricing_period,
    :location,
    :cover_image_url,
    :instructor_name,
    :instructor_headshot_url,
    :start_date,
    :end_date,
    :meeting_days,
    :meeting_start_time,
    :meeting_end_time,
    :season,
    :registration_start_date,
    :registration_end_date,
    :provider_id
  ]

  # Fields that program_updated events may change; excludes season and provider_verified
  # which are only set during bootstrap or by provider verification events respectively.
  @update_fields [
    :title,
    :description,
    :category,
    :age_range,
    :price,
    :pricing_period,
    :location,
    :cover_image_url,
    :instructor_name,
    :instructor_headshot_url,
    :start_date,
    :end_date,
    :meeting_days,
    :meeting_start_time,
    :meeting_end_time,
    :registration_start_date,
    :registration_end_date,
    :provider_id,
    :updated_at
  ]

  # Behaviour callbacks ───────────────────────────────────────────────────────

  @impl Projection
  def bootstrap_impl, do: bootstrap_from_write_table()

  @impl Projection
  def handle_event(:program_created, event), do: upsert_listing_from_event(event)
  def handle_event(:program_updated, event), do: update_listing_from_event(event)
  def handle_event(:provider_verified, event), do: set_provider_verification(event.payload.provider_id, true)
  def handle_event(:provider_unverified, event), do: set_provider_verification(event.payload.provider_id, false)

  # Private ──────────────────────────────────────────────────────────────────

  # Trigger: bootstrap phase — read table may be empty or stale
  # Why: cold start recovery — populate read table from authoritative write table
  # Outcome: program_listings contains one row per program with correct provider_verified status
  defp bootstrap_from_write_table do
    programs = Repo.all(ProgramSchema)

    if programs == [] do
      0
    else
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      entries =
        Enum.map(programs, fn program ->
          program
          |> Map.take(@shared_fields)
          |> Map.put(:id, program.id)
          |> Map.put(:provider_verified, lookup_provider_verified(program.provider_id))
          |> Map.put(:inserted_at, program.inserted_at || now)
          |> Map.put(:updated_at, program.updated_at || now)
        end)

      # Trigger: programs may already have rows in program_listings from a previous run
      # Why: upsert avoids duplicate key errors while keeping data fresh
      # Outcome: all programs projected, preserving original inserted_at on conflicts
      {count, _} =
        Repo.insert_all(ProgramListingSchema, entries,
          on_conflict: {:replace_all_except, [:id, :inserted_at]},
          conflict_target: :id
        )

      count
    end
  end

  # Note: :icon_path was removed from this projection's schema. Stale events from before
  # this change/deploy may carry :icon_path in their payload — it is intentionally
  # discarded. Icon resolution is now handled by ProgramPresenter.icon_name/1
  # at render time using the :category field.

  # Trigger: program_created event received
  # Why: new program needs a listing row; uses upsert for idempotency
  # Outcome: row inserted (or replaced if duplicate event)
  defp upsert_listing_from_event(event) do
    payload = event.payload

    attrs = %{
      id: event.entity_id,
      title: Map.get(payload, :title),
      description: Map.get(payload, :description),
      category: Map.get(payload, :category),
      age_range: Map.get(payload, :age_range),
      price: Map.get(payload, :price),
      pricing_period: Map.get(payload, :pricing_period),
      location: Map.get(payload, :location),
      cover_image_url: Map.get(payload, :cover_image_url),
      instructor_name: extract_instructor_name(payload),
      instructor_headshot_url: extract_instructor_headshot_url(payload),
      start_date: Map.get(payload, :start_date),
      end_date: Map.get(payload, :end_date),
      meeting_days: Map.get(payload, :meeting_days, []),
      meeting_start_time: Map.get(payload, :meeting_start_time),
      meeting_end_time: Map.get(payload, :meeting_end_time),
      season: Map.get(payload, :season),
      registration_start_date: Map.get(payload, :registration_start_date),
      registration_end_date: Map.get(payload, :registration_end_date),
      provider_id: Map.get(payload, :provider_id),
      provider_verified: false
    }

    %ProgramListingSchema{}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: :id
    )
  end

  # Trigger: program_updated event received
  # Why: upsert instead of get-then-update so events for listings missing from the read
  #      table (race with bootstrap) still project instead of being silently dropped.
  #      season and provider_verified are NOT in @update_fields — on conflict they are
  #      preserved; on fresh insert they default to nil/false (next bootstrap corrects).
  # Outcome: listing row updated or inserted with event data
  defp update_listing_from_event(event) do
    program_id = event.entity_id
    payload = event.payload

    attrs = %{
      id: program_id,
      title: Map.get(payload, :title),
      description: Map.get(payload, :description),
      category: Map.get(payload, :category),
      age_range: Map.get(payload, :age_range),
      price: Map.get(payload, :price),
      pricing_period: Map.get(payload, :pricing_period),
      location: Map.get(payload, :location),
      cover_image_url: Map.get(payload, :cover_image_url),
      instructor_name: extract_instructor_name(payload),
      instructor_headshot_url: extract_instructor_headshot_url(payload),
      start_date: Map.get(payload, :start_date),
      end_date: Map.get(payload, :end_date),
      meeting_days: Map.get(payload, :meeting_days, []),
      meeting_start_time: Map.get(payload, :meeting_start_time),
      meeting_end_time: Map.get(payload, :meeting_end_time),
      registration_start_date: Map.get(payload, :registration_start_date),
      registration_end_date: Map.get(payload, :registration_end_date),
      provider_id: Map.get(payload, :provider_id),
      provider_verified: false,
      season: nil
    }

    %ProgramListingSchema{}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!(
      on_conflict: {:replace, @update_fields},
      conflict_target: :id
    )
  end

  # Trigger: provider verification status changed
  # Why: all listings for this provider need their provider_verified flag updated
  # Outcome: bulk update of provider_verified for all matching rows
  defp set_provider_verification(provider_id, verified) do
    from(pl in ProgramListingSchema, where: pl.provider_id == ^provider_id)
    |> Repo.update_all(
      set: [
        provider_verified: verified,
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      ]
    )
  end

  # Trigger: bootstrap needs to know if a provider is currently verified
  # Why: VerifiedProviders projection starts before ProgramListings in the supervision tree,
  #      so it should be available. If not (e.g., test env), default to false.
  # Outcome: returns true/false based on VerifiedProviders state, or false if unavailable
  defp lookup_provider_verified(provider_id) do
    VerifiedProviders.verified?(provider_id)
  catch
    :exit, reason ->
      Logger.warning("ProgramListings: VerifiedProviders unavailable, defaulting to unverified",
        provider_id: provider_id,
        reason: inspect(reason)
      )

      false
  end

  # Trigger: payload may have instructor data in nested or flat format
  # Why: program_created has flat fields, program_updated has nested instructor map
  # Outcome: extract instructor name from whichever format is present
  defp extract_instructor_name(payload) do
    case Map.get(payload, :instructor) do
      %{name: name} -> name
      nil -> Map.get(payload, :instructor_name)
      _ -> nil
    end
  end

  # Trigger: same as extract_instructor_name but for headshot URL
  # Why: consistent extraction logic for both instructor fields
  # Outcome: extract instructor headshot URL from whichever format is present
  defp extract_instructor_headshot_url(payload) do
    case Map.get(payload, :instructor) do
      %{headshot_url: url} -> url
      nil -> Map.get(payload, :instructor_headshot_url)
      _ -> nil
    end
  end
end
