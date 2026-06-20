defmodule KlassHero.Provider.Adapters.Driven.Persistence.Repositories.IdentityVerificationRepository do
  @moduledoc """
  Ecto-based repository for `IdentityVerification` evidence.

  Implements `ForStoringIdentityVerifications` and `ForQueryingIdentityVerifications`. Records are
  append-only per Stripe session; reads dedup on the unique session id or take the latest per
  provider.
  """

  @behaviour KlassHero.Provider.Domain.Ports.ForQueryingIdentityVerifications
  @behaviour KlassHero.Provider.Domain.Ports.ForStoringIdentityVerifications

  use KlassHero.Shared.Interaction

  import Ecto.Query

  alias KlassHero.Provider.Adapters.Driven.Persistence.Mappers.IdentityVerificationMapper
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.IdentityVerificationSchema
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.RepositoryHelpers

  @impl true
  def create(identity_verification) do
    db_interaction operation: :create, entity: "identity_verification" do
      %IdentityVerificationSchema{}
      |> IdentityVerificationSchema.changeset(IdentityVerificationMapper.to_schema(identity_verification))
      |> Repo.insert()
      |> to_domain_result()
    end
  end

  @impl true
  def update(identity_verification) do
    db_interaction operation: :update, entity: "identity_verification" do
      {:ok, schema} = RepositoryHelpers.get_schema_by_uuid(IdentityVerificationSchema, identity_verification.id)

      schema
      |> IdentityVerificationSchema.changeset(IdentityVerificationMapper.to_schema(identity_verification))
      |> Repo.update()
      |> to_domain_result()
    end
  end

  @impl true
  def get_by_session_id(session_id) do
    db_interaction operation: :get_by_session_id, entity: "identity_verification" do
      case Repo.one(from(i in IdentityVerificationSchema, where: i.stripe_session_id == ^session_id)) do
        nil -> {:error, :not_found}
        schema -> {:ok, IdentityVerificationMapper.to_domain(schema)}
      end
    end
  end

  @impl true
  def get_latest_by_provider(provider_id) do
    db_interaction operation: :get_latest_by_provider, entity: "identity_verification" do
      query =
        from(i in IdentityVerificationSchema,
          where: i.provider_id == ^provider_id,
          order_by: [desc: i.inserted_at],
          limit: 1
        )

      case Repo.one(query) do
        nil -> {:error, :not_found}
        schema -> {:ok, IdentityVerificationMapper.to_domain(schema)}
      end
    end
  end

  defp to_domain_result({:ok, schema}), do: {:ok, IdentityVerificationMapper.to_domain(schema)}
  defp to_domain_result({:error, _} = error), do: error
end
