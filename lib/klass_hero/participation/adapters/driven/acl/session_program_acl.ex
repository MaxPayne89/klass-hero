defmodule KlassHero.Participation.Adapters.Driven.ACL.SessionProgramAcl do
  @moduledoc """
  Anti-corruption layer for session reads that reach across context boundaries
  into the `programs` and `providers` tables by name.

  These queries join Program Catalog / Provider tables directly rather than going
  through their public APIs — an isolated, known boundary compromise kept out of
  the context root. A follow-up issue tracks routing them through the owning
  contexts' public APIs.
  """

  use KlassHero.Shared.Interaction

  import Ecto.Query

  alias KlassHero.Participation.ParticipationRecord
  alias KlassHero.Participation.ProgramSession
  alias KlassHero.Repo

  # Statuses that count as "checked in" for attendance tallies
  @checked_in_statuses ~w(checked_in checked_out)

  @doc "Lists a provider's sessions on a date, joining the `programs` table for ownership."
  def list_by_provider_and_date(provider_id, date) when is_binary(provider_id) do
    db_interaction operation: :list_by_provider_and_date, entity: "session" do
      from(s in ProgramSession,
        join: p in "programs",
        on: p.id == s.program_id,
        where: p.provider_id == type(^provider_id, Ecto.UUID) and s.session_date == ^date,
        order_by: [asc: s.start_time]
      )
      |> Repo.all()
    end
  end

  @doc "Resolves a program's title from the `programs` table."
  def get_program_name(program_id) when is_binary(program_id) do
    db_interaction operation: :get_program_name, entity: "session" do
      from(p in "programs",
        where: p.id == type(^program_id, Ecto.UUID),
        select: p.title
      )
      |> Repo.one()
    end
  end

  @doc "Admin session listing with per-session attendance tallies, joining `programs` and `providers`."
  def list_admin_sessions(filters) when is_map(filters) do
    db_interaction operation: :list_admin_sessions, entity: "session" do
      ProgramSession
      |> join(:inner, [s], p in "programs", on: p.id == s.program_id)
      |> join(:left, [s, _p], pr in ParticipationRecord, on: pr.session_id == s.id)
      |> join(:inner, [_s, p, _pr], prov in "providers", on: prov.id == p.provider_id)
      |> apply_admin_filters(filters)
      |> group_by([s, p, _pr, prov], [s.id, p.title, prov.business_name])
      |> select([s, p, _pr, prov], %{
        id: s.id,
        program_id: s.program_id,
        program_name: p.title,
        provider_name: prov.business_name,
        session_date: s.session_date,
        start_time: s.start_time,
        end_time: s.end_time,
        status: s.status,
        checked_in_count:
          count(
            fragment(
              "CASE WHEN ? = ANY(?) THEN 1 END",
              _pr.status,
              ^@checked_in_statuses
            )
          ),
        total_count: count(_pr.id)
      })
      |> order_by([s, _p, _pr, _prov], asc: s.session_date, asc: s.start_time)
      |> Repo.all()
      |> Enum.map(&atomize_status/1)
    end
  end

  defp apply_admin_filters(query, filters) do
    query
    |> maybe_filter_date(filters)
    |> maybe_filter_date_range(filters)
    |> maybe_filter_provider(filters)
    |> maybe_filter_program(filters)
    |> maybe_filter_status(filters)
  end

  defp maybe_filter_date(query, %{date: date}), do: where(query, [s, _p, _pr, _prov], s.session_date == ^date)
  defp maybe_filter_date(query, _), do: query

  defp maybe_filter_date_range(query, %{date_from: from, date_to: to}),
    do: where(query, [s, _p, _pr, _prov], s.session_date >= ^from and s.session_date <= ^to)

  defp maybe_filter_date_range(query, _), do: query

  defp maybe_filter_provider(query, %{provider_id: id}),
    do: where(query, [_s, _p, _pr, prov], prov.id == type(^id, Ecto.UUID))

  defp maybe_filter_provider(query, _), do: query

  defp maybe_filter_program(query, %{program_id: id}),
    do: where(query, [s, _p, _pr, _prov], s.program_id == type(^id, Ecto.UUID))

  defp maybe_filter_program(query, _), do: query

  defp maybe_filter_status(query, %{status: status}),
    do: where(query, [s, _p, _pr, _prov], s.status == ^to_string(status))

  defp maybe_filter_status(query, _), do: query

  defp atomize_status(%{status: status} = map) when is_binary(status),
    do: %{map | status: String.to_existing_atom(status)}

  defp atomize_status(map), do: map
end
