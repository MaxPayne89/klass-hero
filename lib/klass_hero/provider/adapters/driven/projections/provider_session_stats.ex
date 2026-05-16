defmodule KlassHero.Provider.Adapters.Driven.Projections.ProviderSessionStats do
  @moduledoc """
  Event-driven projection maintaining the `provider_session_stats` read table.

  Subscribes to `:session_completed` integration events from the Participation
  context and maintains a denormalised counter of completed sessions per
  provider+program pair.

  Built on `KlassHero.Shared.Projection` (base) + `Projection.WithBootstrapRetry`
  (linear-backoff retry on transient bootstrap failure).

  ## Event handling

  - `:session_completed` — atomic SQL increment of `sessions_completed_count`
    via `INSERT ... ON CONFLICT DO UPDATE SET count = count + 1`. Broadcasts a
    `:session_stats_updated` PubSub message to the provider's stats topic so the
    dashboard LiveView can refresh.
  """

  use KlassHero.Shared.Projection,
    topics: ["integration:participation:session_completed"]

  use KlassHero.Shared.Projection.WithBootstrapRetry

  import Ecto.Query

  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.SessionStatsSchema
  alias KlassHero.Repo
  alias KlassHero.Shared.Domain.Events.IntegrationEvent
  alias KlassHero.Shared.Projection

  @acl Application.compile_env!(:klass_hero, [:provider, :for_resolving_session_stats])

  # Behaviour callbacks ───────────────────────────────────────────────────────

  @impl Projection
  def bootstrap_impl, do: bootstrap_counts()

  @impl Projection
  def handle_event(:session_completed, %IntegrationEvent{} = event) do
    %{provider_id: provider_id, program_id: program_id, program_title: program_title} =
      event.payload

    upsert_session_count(provider_id, program_id, program_title)
    notify_dashboard(provider_id)
  end

  # Private ──────────────────────────────────────────────────────────────────

  # Trigger: bootstrap phase -- read table may be empty or stale
  # Why: cold start recovery -- populate read table from ACL cross-context query
  # Outcome: provider_session_stats contains one row per provider+program with correct counts
  defp bootstrap_counts do
    case @acl.list_completed_session_counts() do
      {:ok, []} ->
        0

      {:ok, rows} ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        entries =
          Enum.map(rows, fn row ->
            %{
              id: Ecto.UUID.generate(),
              provider_id: row.provider_id,
              program_id: row.program_id,
              program_title: row.program_title,
              sessions_completed_count: row.sessions_completed_count,
              inserted_at: now,
              updated_at: now
            }
          end)

        {count, _} =
          Repo.insert_all(SessionStatsSchema, entries,
            on_conflict: {:replace_all_except, [:id, :inserted_at]},
            conflict_target: [:provider_id, :program_id]
          )

        count

      {:error, reason} ->
        raise "Bootstrap ACL query failed: #{inspect(reason)}"
    end
  end

  # Trigger: session_completed event received
  # Why: atomic increment avoids race conditions with concurrent events
  # Outcome: row inserted with count=1 or existing count incremented by 1
  defp upsert_session_count(provider_id, program_id, program_title) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %SessionStatsSchema{}
    |> Ecto.Changeset.change(%{
      id: Ecto.UUID.generate(),
      provider_id: provider_id,
      program_id: program_id,
      program_title: program_title,
      sessions_completed_count: 1,
      inserted_at: now,
      updated_at: now
    })
    |> Repo.insert!(
      on_conflict:
        from(s in SessionStatsSchema,
          update: [
            set: [
              sessions_completed_count: fragment("? + 1", s.sessions_completed_count),
              program_title: ^program_title,
              updated_at: ^now
            ]
          ]
        ),
      conflict_target: [:provider_id, :program_id]
    )
  end

  # Trigger: upsert completed successfully
  # Why: dashboard LiveView needs to know stats changed to refresh the counter
  # Outcome: PubSub broadcast to provider-specific topic
  defp notify_dashboard(provider_id) do
    Phoenix.PubSub.broadcast(
      KlassHero.PubSub,
      "provider:#{provider_id}:stats_updated",
      :session_stats_updated
    )
  end
end
