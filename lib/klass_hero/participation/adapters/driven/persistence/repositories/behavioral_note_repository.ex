defmodule KlassHero.Participation.Adapters.Driven.Persistence.Repositories.BehavioralNoteRepository do
  @moduledoc """
  Ecto-based implementation of the behavioral note repository.

  Implements the ForManagingBehavioralNotes port using PostgreSQL via Ecto.
  """

  @behaviour KlassHero.Participation.Domain.Ports.ForManagingBehavioralNotes
  @behaviour KlassHero.Participation.Domain.Ports.ForQueryingBehavioralNotes

  import Ecto.Query

  alias KlassHero.Participation.Adapters.Driven.Persistence.Mappers.BehavioralNoteMapper
  alias KlassHero.Participation.Adapters.Driven.Persistence.Queries.BehavioralNoteQueries
  alias KlassHero.Participation.Adapters.Driven.Persistence.Schemas.BehavioralNoteSchema
  alias KlassHero.Participation.Domain.Models.BehavioralNote
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.EctoErrorHelpers
  alias KlassHero.Shared.Adapters.Driven.Persistence.RepositoryHelpers

  require Logger

  @impl true
  def create(%BehavioralNote{} = note) do
    attrs = BehavioralNoteMapper.to_persistence(note)

    attrs
    |> BehavioralNoteSchema.create_changeset()
    |> Repo.insert()
    |> handle_insert_result()
  end

  @impl true
  def get_by_id(id) when is_binary(id) do
    RepositoryHelpers.get_by_id(BehavioralNoteSchema, id, BehavioralNoteMapper)
  end

  @impl true
  def update(%BehavioralNote{} = note) do
    case Repo.get(BehavioralNoteSchema, note.id) do
      nil ->
        {:error, :not_found}

      schema ->
        attrs = BehavioralNoteMapper.update_schema(schema, note)

        schema
        |> BehavioralNoteSchema.update_changeset(attrs)
        |> Repo.update()
        |> handle_update_result()
    end
  end

  @impl true
  def list_pending_by_parent(parent_id) when is_binary(parent_id) do
    BehavioralNoteQueries.base()
    |> BehavioralNoteQueries.by_parent(parent_id)
    |> BehavioralNoteQueries.pending()
    |> BehavioralNoteQueries.order_by_submitted_desc()
    |> Repo.all()
    |> Enum.map(&BehavioralNoteMapper.to_domain/1)
  end

  @impl true
  def list_approved_by_child(child_id) when is_binary(child_id) do
    BehavioralNoteQueries.base()
    |> BehavioralNoteQueries.by_child(child_id)
    |> BehavioralNoteQueries.approved()
    |> BehavioralNoteQueries.order_by_submitted_desc()
    |> Repo.all()
    |> Enum.map(&BehavioralNoteMapper.to_domain/1)
  end

  @impl true
  def list_approved_by_children(child_ids) when is_list(child_ids) do
    BehavioralNoteQueries.base()
    |> BehavioralNoteQueries.approved()
    |> where([note: n], n.child_id in ^child_ids)
    |> BehavioralNoteQueries.order_by_submitted_desc()
    |> Repo.all()
    |> Enum.map(&BehavioralNoteMapper.to_domain/1)
    |> Enum.group_by(& &1.child_id)
  end

  @impl true
  def list_by_records_and_provider(record_ids, provider_id) when is_list(record_ids) and is_binary(provider_id) do
    BehavioralNoteQueries.base()
    |> BehavioralNoteQueries.by_participation_records(record_ids)
    |> BehavioralNoteQueries.by_provider(provider_id)
    |> Repo.all()
    |> Enum.map(&BehavioralNoteMapper.to_domain/1)
  end

  @impl true
  def get_by_id_and_parent(id, parent_id) when is_binary(id) and is_binary(parent_id) do
    BehavioralNoteQueries.base()
    |> BehavioralNoteQueries.by_parent(parent_id)
    |> where([note: n], n.id == ^id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      schema -> {:ok, BehavioralNoteMapper.to_domain(schema)}
    end
  end

  @impl true
  def get_by_id_and_provider(id, provider_id) when is_binary(id) and is_binary(provider_id) do
    BehavioralNoteQueries.base()
    |> BehavioralNoteQueries.by_provider(provider_id)
    |> where([note: n], n.id == ^id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      schema -> {:ok, BehavioralNoteMapper.to_domain(schema)}
    end
  end

  @impl true
  def get_by_participation_record_and_provider(participation_record_id, provider_id)
      when is_binary(participation_record_id) and is_binary(provider_id) do
    result =
      BehavioralNoteQueries.base()
      |> BehavioralNoteQueries.by_participation_record(participation_record_id)
      |> BehavioralNoteQueries.by_provider(provider_id)
      |> Repo.one()

    case result do
      nil -> {:error, :not_found}
      schema -> {:ok, BehavioralNoteMapper.to_domain(schema)}
    end
  end

  @impl true
  def anonymize_all_for_child(child_id, anonymized_attrs) when is_binary(child_id) and is_map(anonymized_attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # update_all bypasses Ecto.Enum casting — convert :status atom to string manually.
    set_fields =
      anonymized_attrs
      |> convert_enum_fields()
      |> Enum.to_list()
      |> Keyword.new()
      |> Keyword.put(:updated_at, now)

    {count, _} =
      BehavioralNoteSchema
      |> where([n], n.child_id == ^child_id)
      |> Repo.update_all(set: set_fields)

    {:ok, count}
  end

  defp handle_insert_result({:ok, schema}) do
    {:ok, BehavioralNoteMapper.to_domain(schema)}
  end

  defp handle_insert_result({:error, %Ecto.Changeset{errors: errors} = changeset}) do
    # Unique constraint on [participation_record_id, provider_id] → :duplicate_note
    if EctoErrorHelpers.any_unique_constraint_violation?(errors) do
      {:error, :duplicate_note}
    else
      Logger.warning("[BehavioralNoteRepository] Validation failed on insert",
        errors: inspect(changeset.errors)
      )

      {:error, :validation_failed}
    end
  end

  defp handle_update_result({:ok, schema}) do
    {:ok, BehavioralNoteMapper.to_domain(schema)}
  end

  defp handle_update_result({:error, %Ecto.Changeset{} = changeset}) do
    Logger.warning("[BehavioralNoteRepository] Validation failed on update",
      errors: inspect(changeset.errors)
    )

    {:error, :validation_failed}
  end

  defp convert_enum_fields(attrs) do
    Map.update(attrs, :status, nil, fn
      value when is_atom(value) and not is_nil(value) -> to_string(value)
      value -> value
    end)
  end
end
