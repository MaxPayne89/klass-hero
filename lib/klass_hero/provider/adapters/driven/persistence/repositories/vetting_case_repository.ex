defmodule KlassHero.Provider.Adapters.Driven.Persistence.Repositories.VettingCaseRepository do
  @moduledoc """
  Ecto-based repository for vetting cases and their verification steps.

  Implements `ForStoringVettingCases` and `ForQueryingVettingCases`. A case and its steps are
  written together in a transaction; reads preload the steps in track order.
  """

  @behaviour KlassHero.Provider.Domain.Ports.ForQueryingVettingCases
  @behaviour KlassHero.Provider.Domain.Ports.ForStoringVettingCases

  use KlassHero.Shared.Interaction

  import Ecto.Query

  alias KlassHero.Provider.Adapters.Driven.Persistence.Mappers.ProviderProfileMapper
  alias KlassHero.Provider.Adapters.Driven.Persistence.Mappers.VerificationStepMapper
  alias KlassHero.Provider.Adapters.Driven.Persistence.Mappers.VettingCaseMapper
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.ProviderProfileSchema
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.VerificationStepSchema
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.VettingCaseSchema
  alias KlassHero.Provider.Domain.Models.VettingCase
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.RepositoryHelpers

  @impl true
  def create(case_) do
    db_interaction operation: :create, entity: "vetting_case" do
      Repo.transaction(fn ->
        {:ok, case_schema} =
          %VettingCaseSchema{}
          |> VettingCaseSchema.changeset(VettingCaseMapper.to_schema(case_))
          |> Repo.insert()

        insert_steps!(case_.steps, case_schema.id)
        reload!(case_schema.id)
      end)
    end
  end

  @impl true
  def update(case_) do
    db_interaction operation: :update, entity: "vetting_case" do
      Repo.transaction(fn ->
        {:ok, schema} = RepositoryHelpers.get_schema_by_uuid(VettingCaseSchema, case_.id)

        {:ok, _} =
          schema
          |> VettingCaseSchema.changeset(VettingCaseMapper.to_schema(case_))
          |> Repo.update()

        Enum.each(case_.steps, &update_step!/1)
        # Return the just-persisted aggregate we already hold rather than re-reading it.
        case_
      end)
    end
  end

  @impl true
  def get_by_provider(provider_id) do
    db_interaction operation: :get_by_provider, entity: "vetting_case" do
      case Repo.one(from(c in VettingCaseSchema, where: c.provider_id == ^provider_id)) do
        nil -> create_for_provider(provider_id)
        schema -> {:ok, load_domain(schema.id)}
      end
    end
  end

  # Lazy backfill: providers created before the vetting engine (or before their track was wired)
  # have no case row. Rather than treat that as a defect, build the case for the provider's track
  # on first read so document/identity events can advance it. A missing *provider* is still a real
  # `:not_found`. Race-safe: the `provider_id` unique index makes one concurrent insert win; the
  # loser rolls back and re-reads the winner, so we never crash or duplicate.
  defp create_for_provider(provider_id) do
    case provider_entity_type(provider_id) do
      {:error, :not_found} ->
        {:error, :not_found}

      {:ok, entity_type} ->
        case_ = VettingCase.new_for_track(provider_id, entity_type)

        Repo.transaction(fn ->
          case insert_case(case_) do
            {:ok, case_schema} ->
              insert_steps!(case_.steps, case_schema.id)
              reload!(case_schema.id)

            {:error, %Ecto.Changeset{}} ->
              Repo.rollback(:already_exists)
          end
        end)
        |> case do
          {:ok, domain} -> {:ok, domain}
          {:error, :already_exists} -> {:ok, load_by_provider!(provider_id)}
        end
    end
  end

  defp provider_entity_type(provider_id) do
    case Repo.one(from(p in ProviderProfileSchema, where: p.id == ^provider_id)) do
      nil -> {:error, :not_found}
      schema -> {:ok, ProviderProfileMapper.to_domain(schema).entity_type}
    end
  end

  defp insert_case(case_) do
    %VettingCaseSchema{}
    |> VettingCaseSchema.changeset(VettingCaseMapper.to_schema(case_))
    |> Repo.insert()
  end

  defp load_by_provider!(provider_id) do
    schema = Repo.one!(from(c in VettingCaseSchema, where: c.provider_id == ^provider_id))
    load_domain(schema.id)
  end

  defp insert_steps!(steps, case_id) do
    Enum.each(steps, fn step ->
      attrs = step |> VerificationStepMapper.to_schema() |> Map.put(:vetting_case_id, case_id)

      {:ok, _} =
        %VerificationStepSchema{}
        |> VerificationStepSchema.changeset(attrs)
        |> Repo.insert()
    end)
  end

  defp update_step!(step) do
    {:ok, schema} = RepositoryHelpers.get_schema_by_uuid(VerificationStepSchema, step.id)

    {:ok, _} =
      schema
      |> VerificationStepSchema.changeset(VerificationStepMapper.to_schema(step))
      |> Repo.update()
  end

  defp reload!(case_id), do: load_domain(case_id)

  defp load_domain(case_id) do
    VettingCaseSchema
    |> Repo.get!(case_id)
    |> Repo.preload(steps: from(s in VerificationStepSchema, order_by: s.inserted_at))
    |> VettingCaseMapper.to_domain()
  end
end
