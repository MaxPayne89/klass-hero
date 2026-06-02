defmodule KlassHero.Participation.Adapters.Driven.Persistence.Repositories.SessionRepository do
  @moduledoc """
  Ecto-based implementation of the session repository.

  Implements the ForManagingSessions port using PostgreSQL via Ecto.
  """

  @behaviour KlassHero.Participation.Domain.Ports.ForManagingSessions
  @behaviour KlassHero.Participation.Domain.Ports.ForQueryingSessions

  import Ecto.Query

  alias KlassHero.Participation.Adapters.Driven.Persistence.Mappers.ProgramSessionMapper
  alias KlassHero.Participation.Adapters.Driven.Persistence.Schemas.ParticipationRecordSchema
  alias KlassHero.Participation.Adapters.Driven.Persistence.Schemas.ProgramSessionSchema
  alias KlassHero.Participation.Domain.Models.ProgramSession
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.EctoErrorHelpers
  alias KlassHero.Shared.Adapters.Driven.Persistence.RepositoryHelpers
  alias KlassHero.Shared.ErrorIds

  # Statuses that count as "checked in" for attendance tallies
  @checked_in_statuses ~w(checked_in checked_out)

  @impl true
  def create(%ProgramSession{} = session) do
    attrs = ProgramSessionMapper.to_persistence(session)

    attrs
    |> ProgramSessionSchema.create_changeset()
    |> Repo.insert()
    |> handle_insert_result()
  end

  @impl true
  def get_by_id(id) when is_binary(id) do
    RepositoryHelpers.get_by_id(ProgramSessionSchema, id, ProgramSessionMapper)
  end

  @impl true
  def list_by_program(program_id) when is_binary(program_id) do
    from(s in ProgramSessionSchema,
      where: s.program_id == ^program_id,
      order_by: [asc: s.session_date, asc: s.start_time]
    )
    |> Repo.all()
    |> Enum.map(&ProgramSessionMapper.to_domain/1)
  end

  @impl true
  def list_today_sessions(date) do
    from(s in ProgramSessionSchema,
      where: s.session_date == ^date,
      order_by: [asc: s.start_time]
    )
    |> Repo.all()
    |> Enum.map(&ProgramSessionMapper.to_domain/1)
  end

  @impl true
  def update(%ProgramSession{} = session) do
    with {:ok, schema} <-
           RepositoryHelpers.get_schema_by_uuid(ProgramSessionSchema, session.id) do
      attrs = ProgramSessionMapper.update_schema(schema, session)

      schema
      |> ProgramSessionSchema.update_changeset(attrs)
      |> Repo.update()
      |> handle_update_result()
    end
  end

  @impl true
  def list_by_provider_and_date(provider_id, date) when is_binary(provider_id) do
    from(s in ProgramSessionSchema,
      join: p in "programs",
      on: p.id == s.program_id,
      where: p.provider_id == type(^provider_id, Ecto.UUID) and s.session_date == ^date,
      order_by: [asc: s.start_time]
    )
    |> Repo.all()
    |> Enum.map(&ProgramSessionMapper.to_domain/1)
  end

  @impl true
  def get_many_by_ids(ids) when is_list(ids) do
    from(s in ProgramSessionSchema,
      where: s.id in ^ids
    )
    |> Repo.all()
    |> Enum.map(&ProgramSessionMapper.to_domain/1)
  end

  @impl true
  def get_program_name(program_id) when is_binary(program_id) do
    from(p in "programs",
      where: p.id == type(^program_id, Ecto.UUID),
      select: p.title
    )
    |> Repo.one()
  end

  @impl true
  def list_admin_sessions(filters) when is_map(filters) do
    ProgramSessionSchema
    |> join(:inner, [s], p in "programs", on: p.id == s.program_id)
    |> join(:left, [s, _p], pr in ParticipationRecordSchema, on: pr.session_id == s.id)
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

  defp handle_insert_result({:ok, schema}) do
    {:ok, ProgramSessionMapper.to_domain(schema)}
  end

  defp handle_insert_result({:error, %Ecto.Changeset{errors: errors} = changeset}) do
    if EctoErrorHelpers.any_unique_constraint_violation?(errors) do
      {:error, :duplicate_session}
    else
      {:error, ErrorIds.session_create_failed(changeset)}
    end
  end

  defp handle_update_result({:ok, schema}) do
    {:ok, ProgramSessionMapper.to_domain(schema)}
  end

  defp handle_update_result({:error, %Ecto.Changeset{} = changeset}) do
    if changeset.errors[:lock_version] do
      {:error, :stale_data}
    else
      {:error, ErrorIds.session_update_failed(changeset)}
    end
  end
end
