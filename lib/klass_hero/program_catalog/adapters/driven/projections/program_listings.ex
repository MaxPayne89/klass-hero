defmodule KlassHero.ProgramCatalog.Adapters.Driven.Projections.ProgramListings do
  @moduledoc """
  Event-driven projection maintaining the `program_listings` read table.

  Mirrors program data from the write table so Program Catalog queries can serve
  denormalised reads without joins. It holds *no* Provider state: since #1195,
  provider name and vetting state are read from Provider's facade per render, so
  this projection subscribes to Program Catalog's own events only.

  Built on `KlassHero.Shared.Projection` (base) + `Projection.WithBootstrapRetry`
  (linear-backoff retry on transient bootstrap failure).

  ## Event handling

  - `:program_created` — inserts a new listing row
  - `:program_updated` — updates listing fields (preserves season)

  Bang functions (`Repo.insert!`, `Repo.update!`) are used intentionally — if a
  DB write fails, the GenServer crashes and the supervisor restarts it, triggering
  a full re-bootstrap. Transient failures resolve via restart; persistent failures
  surface as repeated crashes (hitting `max_restarts`).
  """

  use KlassHero.Shared.Projection,
    topics: [
      "integration:program_catalog:program_created",
      "integration:program_catalog:program_updated"
    ]

  use KlassHero.Shared.Projection.WithBootstrapRetry

  alias KlassHero.ProgramCatalog.Program
  alias KlassHero.ProgramCatalog.ProgramListing
  alias KlassHero.Repo
  alias KlassHero.Shared.Projection

  @shared_fields [
    :title,
    :subtitle,
    :description,
    :category,
    :age_range,
    :price,
    :pricing_period,
    :location,
    :cover_image_url,
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

  # Excludes season: it is bootstrap-only.
  @update_fields [
    :title,
    :subtitle,
    :description,
    :category,
    :age_range,
    :price,
    :pricing_period,
    :location,
    :cover_image_url,
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

  @impl Projection
  def bootstrap_impl, do: bootstrap_from_write_table()

  @impl Projection
  def handle_event(:program_created, event), do: upsert_listing_from_event(event)
  def handle_event(:program_updated, event), do: update_listing_from_event(event)

  defp bootstrap_from_write_table do
    programs = Repo.all(Program)

    if programs == [] do
      0
    else
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      entries =
        Enum.map(programs, fn program ->
          program
          |> Map.take(@shared_fields)
          |> Map.put(:id, program.id)
          |> Map.put(:inserted_at, program.inserted_at || now)
          |> Map.put(:updated_at, program.updated_at || now)
        end)

      {count, _} =
        Repo.insert_all(ProgramListing, entries,
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

  defp upsert_listing_from_event(event) do
    payload = event.payload

    attrs = %{
      id: event.entity_id,
      title: Map.get(payload, :title),
      subtitle: Map.get(payload, :subtitle),
      description: Map.get(payload, :description),
      category: Map.get(payload, :category),
      age_range: Map.get(payload, :age_range),
      price: Map.get(payload, :price),
      pricing_period: Map.get(payload, :pricing_period),
      location: Map.get(payload, :location),
      cover_image_url: Map.get(payload, :cover_image_url),
      start_date: Map.get(payload, :start_date),
      end_date: Map.get(payload, :end_date),
      meeting_days: Map.get(payload, :meeting_days, []),
      meeting_start_time: Map.get(payload, :meeting_start_time),
      meeting_end_time: Map.get(payload, :meeting_end_time),
      season: Map.get(payload, :season),
      registration_start_date: Map.get(payload, :registration_start_date),
      registration_end_date: Map.get(payload, :registration_end_date),
      provider_id: Map.get(payload, :provider_id)
    }

    %ProgramListing{}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: :id
    )
  end

  # Upsert (not get-then-update) so events that race with bootstrap still project rather than being silently dropped.
  # season is not in @update_fields: on conflict it is preserved; fresh inserts default to nil and are corrected
  # by the next bootstrap.
  defp update_listing_from_event(event) do
    program_id = event.entity_id
    payload = event.payload

    attrs = %{
      id: program_id,
      title: Map.get(payload, :title),
      subtitle: Map.get(payload, :subtitle),
      description: Map.get(payload, :description),
      category: Map.get(payload, :category),
      age_range: Map.get(payload, :age_range),
      price: Map.get(payload, :price),
      pricing_period: Map.get(payload, :pricing_period),
      location: Map.get(payload, :location),
      cover_image_url: Map.get(payload, :cover_image_url),
      start_date: Map.get(payload, :start_date),
      end_date: Map.get(payload, :end_date),
      meeting_days: Map.get(payload, :meeting_days, []),
      meeting_start_time: Map.get(payload, :meeting_start_time),
      meeting_end_time: Map.get(payload, :meeting_end_time),
      registration_start_date: Map.get(payload, :registration_start_date),
      registration_end_date: Map.get(payload, :registration_end_date),
      provider_id: Map.get(payload, :provider_id),
      season: nil
    }

    %ProgramListing{}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!(
      on_conflict: {:replace, @update_fields},
      conflict_target: :id
    )
  end
end
