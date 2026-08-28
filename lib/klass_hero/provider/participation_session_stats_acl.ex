defmodule KlassHero.Provider.ParticipationSessionStatsACL do
  @moduledoc """
  Anti-corruption layer for resolving session completion counts from Participation.

  Joins Participation's `program_sessions` with Program Catalog's `programs` to count
  a provider's completed sessions. Read live on the provider overview — there is no
  denormalised counter behind it.

  ## Why an ACL rather than facade calls

  ADR 0015's fourth justification — a query no facade expresses. Provider owns neither
  table: `program_sessions` belongs to Participation and carries no `provider_id`, so
  ownership is only reachable by joining `programs`. Serving this through facades would
  mean fetching every one of a provider's programs and every session of each, then
  counting in Elixir. Naming the justification is a requirement of that ADR, not a
  courtesy.

  A query failure raises rather than returning a default. A dashboard that renders `0`
  because the database was unreachable is indistinguishable from one that renders `0`
  because nothing has happened yet, and the second is a fact while the first is a lie.
  """

  use KlassHero.Shared.Tracing

  import Ecto.Query

  alias KlassHero.Repo

  @doc """
  Counts the provider's completed sessions across every program they own.
  """
  # Two foreign contexts, one span on the `FROM` table's — the shape
  # `family/child_enrollment_acl.ex` already uses for its two-table join.
  @spec total_completed_sessions(String.t()) :: non_neg_integer()
  def total_completed_sessions(provider_id) when is_binary(provider_id) do
    acl_span source: "provider", target: "participation" do
      from(s in "program_sessions",
        join: p in "programs",
        on: s.program_id == p.id,
        where: s.status == "completed" and p.provider_id == type(^provider_id, :binary_id),
        select: count(s.id)
      )
      |> Repo.one()
    end
  end
end
