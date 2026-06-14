defmodule KlassHero.Participation.Adapters.Driven.Persistence.Repositories.ParticipationRepository do
  @moduledoc """
  Ecto-based implementation of the participation record repository.

  Implements the ForManagingParticipation port using PostgreSQL via Ecto.
  """

  @behaviour KlassHero.Participation.Domain.Ports.ForManagingParticipation
  @behaviour KlassHero.Participation.Domain.Ports.ForQueryingParticipation

  use KlassHero.Shared.Interaction

  import Ecto.Query

  alias Ecto.Multi
  alias KlassHero.Participation.Adapters.Driven.Persistence.Mappers.ParticipationRecordMapper
  alias KlassHero.Participation.Adapters.Driven.Persistence.Queries.ParticipationQueries
  alias KlassHero.Participation.Adapters.Driven.Persistence.Schemas.ParticipationRecordSchema
  alias KlassHero.Participation.Adapters.Driven.Persistence.Schemas.ProgramSessionSchema
  alias KlassHero.Participation.Domain.Models.ParticipationRecord
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.RepositoryHelpers
  alias KlassHero.Shared.ErrorIds

  @impl true
  def create(%ParticipationRecord{} = record) do
    db_interaction operation: :create, entity: "participation" do
      attrs = ParticipationRecordMapper.to_persistence(record)

      attrs
      |> ParticipationRecordSchema.create_changeset()
      |> Repo.insert()
      |> handle_insert_result()
    end
  end

  @impl true
  def get_by_id(id) when is_binary(id) do
    db_interaction operation: :get_by_id, entity: "participation" do
      RepositoryHelpers.get_by_id(ParticipationRecordSchema, id, ParticipationRecordMapper)
    end
  end

  @impl true
  def list_by_session(session_id) when is_binary(session_id) do
    db_interaction operation: :list_by_session, entity: "participation" do
      ParticipationQueries.base()
      |> ParticipationQueries.by_session(session_id)
      |> ParticipationQueries.order_by_inserted_desc()
      |> Repo.all()
      |> Enum.map(&ParticipationRecordMapper.to_domain/1)
    end
  end

  @impl true
  def list_by_child(child_id) when is_binary(child_id) do
    db_interaction operation: :list_by_child, entity: "participation" do
      ParticipationQueries.base()
      |> ParticipationQueries.by_child(child_id)
      |> ParticipationQueries.preload_session()
      |> ParticipationQueries.order_by_inserted_desc()
      |> Repo.all()
      |> Enum.map(&ParticipationRecordMapper.to_domain/1)
    end
  end

  @impl true
  def list_by_child_and_date_range(child_id, start_date, end_date) when is_binary(child_id) do
    db_interaction operation: :list_by_child_and_date_range, entity: "participation" do
      ParticipationQueries.base()
      |> ParticipationQueries.by_child(child_id)
      |> ParticipationQueries.by_date_range(start_date, end_date)
      |> ParticipationQueries.order_by_session_date_desc()
      |> Repo.all()
      |> Enum.map(&ParticipationRecordMapper.to_domain/1)
    end
  end

  @impl true
  def list_by_children(child_ids) when is_list(child_ids) do
    db_interaction operation: :list_by_children, entity: "participation" do
      ParticipationQueries.base()
      |> ParticipationQueries.by_children(child_ids)
      |> ParticipationQueries.preload_session()
      |> ParticipationQueries.order_by_inserted_desc()
      |> Repo.all()
      |> Enum.map(&ParticipationRecordMapper.to_domain/1)
    end
  end

  @impl true
  def list_by_children_and_date_range(child_ids, start_date, end_date) when is_list(child_ids) do
    db_interaction operation: :list_by_children_and_date_range, entity: "participation" do
      ParticipationQueries.base()
      |> ParticipationQueries.by_children(child_ids)
      |> ParticipationQueries.by_date_range(start_date, end_date)
      |> ParticipationQueries.order_by_session_date_desc()
      |> Repo.all()
      |> Enum.map(&ParticipationRecordMapper.to_domain/1)
    end
  end

  @impl true
  def update(%ParticipationRecord{} = record) do
    db_interaction operation: :update, entity: "participation" do
      with {:ok, schema} <-
             RepositoryHelpers.get_schema_by_uuid(ParticipationRecordSchema, record.id) do
        attrs = ParticipationRecordMapper.update_schema(schema, record)

        schema
        |> ParticipationRecordSchema.update_changeset(attrs)
        |> do_update()
      end
    end
  end

  defp do_update(changeset) do
    Repo.update(changeset)
    |> handle_update_result()
  rescue
    Ecto.StaleEntryError ->
      {:error, :stale_data}
  end

  @impl true
  def create_batch(records) when is_list(records) do
    db_interaction operation: :create_batch, entity: "participation" do
      multi =
        records
        |> Enum.with_index()
        |> Enum.reduce(Multi.new(), fn {record, index}, multi ->
          attrs = ParticipationRecordMapper.to_persistence(record)
          changeset = ParticipationRecordSchema.create_changeset(attrs)
          Multi.insert(multi, {:record, index}, changeset)
        end)

      case Repo.transaction(multi) do
        {:ok, results} ->
          records =
            results
            |> Enum.sort_by(fn {{:record, index}, _} -> index end)
            |> Enum.map(fn {_, schema} -> ParticipationRecordMapper.to_domain(schema) end)

          {:ok, records}

        {:error, _operation, changeset, _changes} ->
          {:error, changeset}
      end
    end
  end

  @impl true
  def mark_absent_batch([]), do: {:ok, 0}

  def mark_absent_batch(record_ids) when is_list(record_ids) do
    db_interaction operation: :mark_absent_batch, entity: "participation" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {count, _} =
        from(r in ParticipationRecordSchema,
          where: r.id in ^record_ids and r.status == :registered
        )
        |> Repo.update_all(inc: [lock_version: 1], set: [status: :absent, updated_at: now])

      {:ok, count}
    end
  end

  @impl true
  def seed_batch(_session_id, []), do: {:ok, 0}

  def seed_batch(session_id, child_ids) when is_binary(session_id) and is_list(child_ids) do
    db_interaction operation: :seed_batch, entity: "participation" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      rows =
        Enum.map(child_ids, fn child_id ->
          %{
            id: Ecto.UUID.generate(),
            session_id: session_id,
            child_id: child_id,
            status: :registered,
            lock_version: 1,
            inserted_at: now,
            updated_at: now
          }
        end)

      {count, _} =
        Repo.insert_all(
          ParticipationRecordSchema,
          rows,
          on_conflict: :nothing,
          conflict_target: [:session_id, :child_id]
        )

      {:ok, count}
    end
  end

  @doc """
  Lists participation records for a session with child names resolved.

  This is a convenience function that joins session data for roster display.
  """
  @spec list_by_session_with_session(String.t()) :: [
          {ParticipationRecord.t(), ProgramSessionSchema.t()}
        ]
  def list_by_session_with_session(session_id) when is_binary(session_id) do
    db_interaction operation: :list_by_session_with_session, entity: "participation" do
      from(r in ParticipationRecordSchema,
        join: s in ProgramSessionSchema,
        on: r.session_id == s.id,
        where: r.session_id == ^session_id,
        order_by: [asc: r.inserted_at],
        select: {r, s}
      )
      |> Repo.all()
      |> Enum.map(fn {record_schema, session_schema} ->
        {ParticipationRecordMapper.to_domain(record_schema), session_schema}
      end)
    end
  end

  defp handle_insert_result({:ok, schema}) do
    {:ok, ParticipationRecordMapper.to_domain(schema)}
  end

  defp handle_insert_result({:error, %Ecto.Changeset{errors: errors} = changeset}) do
    if Keyword.has_key?(errors, :session_id) &&
         match?({_, [constraint: :unique, constraint_name: _]}, errors[:session_id]) do
      {:error, :duplicate_record}
    else
      {:error, ErrorIds.participation_record_create_failed(changeset)}
    end
  end

  defp handle_update_result({:ok, schema}) do
    {:ok, ParticipationRecordMapper.to_domain(schema)}
  end

  defp handle_update_result({:error, %Ecto.Changeset{} = changeset}) do
    if changeset.errors[:lock_version] do
      {:error, :stale_data}
    else
      {:error, ErrorIds.participation_record_update_failed(changeset)}
    end
  end
end
