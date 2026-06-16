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

  alias KlassHero.Provider.Adapters.Driven.Persistence.Mappers.VerificationStepMapper
  alias KlassHero.Provider.Adapters.Driven.Persistence.Mappers.VettingCaseMapper
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.VerificationStepSchema
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.VettingCaseSchema
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
        reload!(case_.id)
      end)
    end
  end

  @impl true
  def get_by_provider(provider_id) do
    db_interaction operation: :get_by_provider, entity: "vetting_case" do
      case Repo.one(from(c in VettingCaseSchema, where: c.provider_id == ^provider_id)) do
        nil -> {:error, :not_found}
        schema -> {:ok, load_domain(schema.id)}
      end
    end
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
