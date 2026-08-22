defmodule KlassHero.Provider.ParticipationSessionStatsACL do
  @moduledoc """
  Anti-corruption layer for resolving session completion counts from Participation.

  Cross-context bootstrap query: joins Participation's `program_sessions` with
  Program Catalog's `programs` to compute counts grouped by (provider_id, program_id).

  Used exclusively during ProviderSessionStats projection bootstrap.

  ## Why an ACL rather than facade calls

  ADR 0015's fourth justification — a query no facade expresses. The grouped count spans
  two foreign contexts in one aggregation; serving it through facades would mean fetching
  every session and every program and counting in Elixir, on the bootstrap path. Naming
  the justification is a requirement of that ADR, not a courtesy.
  """

  use KlassHero.Shared.Tracing

  import Ecto.Query

  alias KlassHero.Repo

  require Logger

  # Two foreign contexts, one span on the `FROM` table's — the shape
  # `family/…/acl/child_enrollment_acl.ex` already uses for its two-table join.
  def list_completed_session_counts do
    results =
      acl_span source: "provider", target: "participation" do
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
      end

    {:ok, results}
  rescue
    error ->
      Logger.error("[ParticipationSessionStatsACL] Bootstrap query failed: #{Exception.message(error)}")

      {:error, :bootstrap_query_failed}
  end
end
