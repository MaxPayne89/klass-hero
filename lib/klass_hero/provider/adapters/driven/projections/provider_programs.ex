defmodule KlassHero.Provider.Adapters.Driven.Projections.ProviderPrograms do
  @moduledoc """
  Event-driven projection maintaining the `provider_programs` read table.

  Mirrors program ownership + display metadata from the Program Catalog context
  so Provider use cases never reach across the context boundary at runtime.

  Built on `KlassHero.Shared.Projection` (base) + `Projection.WithBootstrapRetry`
  (linear-backoff retry on transient bootstrap failure).

  ## Event handling

  - `:program_created` — upsert row keyed by `program_id`
  - `:program_updated` — upsert row keyed by `program_id` (replaces mutable fields)

  Programs in the Program Catalog have no first-class status field today, so this
  projection records every program as `"active"`. The column exists to support
  future filtering (archived/draft) without requiring a migration.
  """

  use KlassHero.Shared.Projection,
    topics: [
      "integration:program_catalog:program_created",
      "integration:program_catalog:program_updated"
    ]

  use KlassHero.Shared.Projection.WithBootstrapRetry

  import Ecto.Query

  alias KlassHero.ProgramCatalog.Program
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.ProviderProgramProjectionSchema
  alias KlassHero.Repo
  alias KlassHero.Shared.Domain.Events.IntegrationEvent
  alias KlassHero.Shared.Projection

  @default_status "active"

  @impl Projection
  def bootstrap_impl, do: bootstrap_from_write_table()

  @impl Projection
  def handle_event(event_type, %IntegrationEvent{} = event) when event_type in [:program_created, :program_updated] do
    upsert_from_event(event)
  end

  defp bootstrap_from_write_table do
    programs =
      Program
      |> select([p], %{program_id: p.id, provider_id: p.provider_id, name: p.title})
      |> Repo.all()

    if programs == [] do
      0
    else
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      rows =
        Enum.map(programs, fn program ->
          Map.merge(program, %{status: @default_status, inserted_at: now, updated_at: now})
        end)

      {count, _} =
        Repo.insert_all(
          ProviderProgramProjectionSchema,
          rows,
          on_conflict: {:replace, [:provider_id, :name, :status, :updated_at]},
          conflict_target: [:program_id]
        )

      count
    end
  end

  defp upsert_from_event(%IntegrationEvent{} = event) do
    payload = event.payload
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs = %{
      program_id: event.entity_id,
      provider_id: Map.fetch!(payload, :provider_id),
      name: extract_name(payload),
      status: extract_status(payload),
      inserted_at: now,
      updated_at: now
    }

    Repo.insert_all(
      ProviderProgramProjectionSchema,
      [attrs],
      on_conflict: {:replace, [:provider_id, :name, :status, :updated_at]},
      conflict_target: [:program_id]
    )
  end

  defp extract_name(%{title: title}) when is_binary(title), do: title
  defp extract_name(%{name: name}) when is_binary(name), do: name

  defp extract_name(payload) do
    Logger.error("ProviderPrograms received event without :title or :name (payload_keys=#{inspect(Map.keys(payload))})")

    raise ArgumentError, "Program payload missing :title or :name field"
  end

  defp extract_status(%{status: status}) when is_binary(status), do: status

  defp extract_status(%{status: status}) when is_atom(status) and status not in [nil, true, false],
    do: Atom.to_string(status)

  defp extract_status(_), do: @default_status
end
