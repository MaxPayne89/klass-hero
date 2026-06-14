defmodule KlassHero.Provider.Adapters.Driven.Persistence.Repositories.ProviderProfileRepository do
  @moduledoc """
  Repository implementation for storing and retrieving provider profiles from the database.

  Implements the ForStoringProviderProfiles port with:
  - Domain entity mapping via ProviderProfileMapper
  - Idiomatic "let it crash" error handling

  Data integrity is enforced at the database level through:
  - NOT NULL constraint on identity_id and business_name
  - UNIQUE constraint on identity_id (prevents duplicate profiles)

  Infrastructure errors (connection, query) are not caught - they crash and
  are handled by the supervision tree.
  """

  @behaviour KlassHero.Provider.Domain.Ports.ForQueryingProviderProfiles
  @behaviour KlassHero.Provider.Domain.Ports.ForStoringProviderProfiles

  use KlassHero.Shared.Interaction

  import Ecto.Query

  alias KlassHero.Provider.Adapters.Driven.Persistence.Mappers.ProviderProfileMapper
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.ProviderProfileSchema
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.EctoErrorHelpers
  alias KlassHero.Shared.Adapters.Driven.Persistence.MapperHelpers
  alias KlassHero.Shared.Adapters.Driven.Persistence.RepositoryHelpers
  alias KlassHero.Shared.ErrorIds

  require Logger

  @impl true
  @doc """
  Creates a new provider profile in the database.

  Returns:
  - `{:ok, ProviderProfile.t()}` on success
  - `{:error, :duplicate_resource}` - Provider profile already exists for this identity_id
  - `{:error, changeset}` - Validation failure
  """
  def create_provider_profile(attrs) when is_map(attrs) do
    db_interaction operation: :create_provider_profile, entity: "provider_profile" do
      schema_attrs =
        attrs
        |> MapperHelpers.normalize_atom_field(:profile_status)

      %ProviderProfileSchema{}
      |> ProviderProfileSchema.changeset(schema_attrs)
      |> Repo.insert()
      |> case do
        {:ok, schema} ->
          {:ok, ProviderProfileMapper.to_domain(schema)}

        {:error, %Ecto.Changeset{errors: errors} = changeset} ->
          if EctoErrorHelpers.unique_constraint_violation?(errors, :identity_id) do
            Logger.warning(
              "[Provider.ProviderProfileRepository] Duplicate provider profile",
              error_id: ErrorIds.provider_duplicate_identity(),
              identity_id: attrs[:identity_id]
            )

            {:error, :duplicate_resource}
          else
            RepositoryHelpers.log_validation_error(
              changeset,
              ErrorIds.provider_profile_validation_failed()
            )

            {:error, changeset}
          end
      end
    end
  end

  @impl true
  @doc """
  Retrieves a provider profile by identity ID from the database.

  Returns:
  - `{:ok, ProviderProfile.t()}` when provider profile is found
  - `{:error, :not_found}` when no provider profile exists with the given identity_id
  """
  def get_by_identity_id(identity_id) when is_binary(identity_id) do
    db_interaction operation: :get_by_identity_id, entity: "provider_profile" do
      case Repo.one(from p in ProviderProfileSchema, where: p.identity_id == ^identity_id) do
        nil -> {:error, :not_found}
        schema -> {:ok, ProviderProfileMapper.to_domain(schema)}
      end
    end
  end

  @impl true
  @doc """
  Checks if a provider profile exists for the given identity ID.

  Returns boolean directly.
  """
  def has_profile?(identity_id) when is_binary(identity_id) do
    db_interaction operation: :has_profile, entity: "provider_profile" do
      ProviderProfileSchema
      |> where([p], p.identity_id == ^identity_id)
      |> Repo.exists?()
    end
  end

  @impl true
  @doc """
  Retrieves a provider profile by its ID.

  Returns:
  - `{:ok, ProviderProfile.t()}` when provider profile is found
  - `{:error, :not_found}` when no provider profile exists with the given ID
  """
  def get(id) when is_binary(id) do
    db_interaction operation: :get, entity: "provider_profile" do
      case Repo.get(ProviderProfileSchema, id) do
        nil -> {:error, :not_found}
        schema -> {:ok, ProviderProfileMapper.to_domain(schema)}
      end
    end
  end

  @impl true
  @doc """
  Updates an existing provider profile in the database.

  Returns:
  - `{:ok, ProviderProfile.t()}` on success
  - `{:error, :not_found}` when provider profile doesn't exist
  - `{:error, changeset}` on validation failure
  """
  def update(provider_profile) do
    db_interaction operation: :update, entity: "provider_profile" do
      with {:ok, schema} <-
             RepositoryHelpers.get_schema_by_uuid(ProviderProfileSchema, provider_profile.id),
           attrs = ProviderProfileMapper.to_schema(provider_profile),
           {:ok, updated} <-
             schema |> ProviderProfileSchema.changeset(attrs) |> Repo.update() do
        {:ok, ProviderProfileMapper.to_domain(updated)}
      end
    end
  end

  @impl true
  @doc """
  Lists all verified provider profile IDs.

  Used by projections and caching layers to track verification status.

  Returns:
  - `{:ok, [String.t()]}` - List of verified provider profile IDs (may be empty)
  """
  def list_verified_ids do
    db_interaction operation: :list_verified_ids, entity: "provider_profile" do
      ids =
        ProviderProfileSchema
        |> where([p], p.verified == true)
        |> select([p], p.id)
        |> Repo.all()

      {:ok, ids}
    end
  end
end
