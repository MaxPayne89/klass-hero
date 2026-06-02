defmodule KlassHero.Provider.Adapters.Driven.ACL.ParticipationSessionStatsACL do
  @moduledoc """
  Anti-corruption layer for resolving session completion counts from Participation.

  Cross-context bootstrap query: joins Participation's `program_sessions` with
  Program Catalog's `programs` to compute counts grouped by (provider_id, program_id).

  Used exclusively during ProviderSessionStats projection bootstrap.
  """

  @behaviour KlassHero.Provider.Domain.Ports.ForResolvingSessionStats

  use KlassHero.Shared.Tracing

  import Ecto.Query

  alias KlassHero.Repo

  require Logger

  @impl true
  def list_completed_session_counts do
    acl_span source: "provider", target: "participation" do
      results =
        from(s in "program_sessions",
          join: p in "programs",
          on: s.program_id == p.id,
          where: s.status == "completed",
          group_by: [p.provider_id, p.id, p.title],
          select: %{
            provider_id: type(p.provider_id, :binary_id),
            program_id: type(p.id, :binary_id),
            program_title: p.title,
            sessions_completed_count: count(s.id)
          }
        )
        |> Repo.all()

      {:ok, results}
    end
  rescue
    error ->
      Logger.error("[ParticipationSessionStatsACL] Bootstrap query failed: #{Exception.message(error)}")

      {:error, :bootstrap_query_failed}
  end
end
