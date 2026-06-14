defmodule KlassHero.Family.Adapters.Driven.Persistence.Repositories.ParentProfileRepository do
  @moduledoc """
  Repository implementation for storing and retrieving parent profiles from the database.

  Implements the ForStoringParentProfiles port with:
  - Domain entity mapping via ParentProfileMapper
  - Idiomatic "let it crash" error handling

  Data integrity is enforced at the database level through:
  - NOT NULL constraint on identity_id
  - UNIQUE constraint on identity_id (prevents duplicate profiles)

  Infrastructure errors (connection, query) are not caught - they crash and
  are handled by the supervision tree.
  """

  @behaviour KlassHero.Family.Domain.Ports.ForQueryingParentProfiles
  @behaviour KlassHero.Family.Domain.Ports.ForStoringParentProfiles

  use KlassHero.Shared.Interaction

  import Ecto.Query

  alias KlassHero.Family.Adapters.Driven.Persistence.Mappers.ParentProfileMapper
  alias KlassHero.Family.Adapters.Driven.Persistence.Schemas.ParentProfileSchema
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.EctoErrorHelpers
  alias KlassHero.Shared.Adapters.Driven.Persistence.MapperHelpers
  alias KlassHero.Shared.ErrorIds

  require Logger

  @impl true
  @doc """
  Creates a new parent profile in the database.

  Returns:
  - `{:ok, ParentProfile.t()}` on success
  - `{:error, :duplicate_resource}` - Parent profile already exists for this identity_id
  - `{:error, changeset}` - Validation failure
  """
  def create_parent_profile(attrs) when is_map(attrs) do
    db_interaction operation: :create_parent_profile, entity: "parent_profile" do
      schema_attrs = MapperHelpers.normalize_subscription_tier(attrs)

      %ParentProfileSchema{}
      |> ParentProfileSchema.changeset(schema_attrs)
      |> Repo.insert()
      |> case do
        {:ok, schema} ->
          {:ok, ParentProfileMapper.to_domain(schema)}

        {:error, %Ecto.Changeset{errors: errors} = changeset} ->
          if EctoErrorHelpers.unique_constraint_violation?(errors, :identity_id) do
            Logger.warning(
              "[Family.ParentProfileRepository] Duplicate parent profile",
              error_id: ErrorIds.parent_duplicate_identity(),
              identity_id: attrs[:identity_id]
            )

            {:error, :duplicate_resource}
          else
            Logger.warning(
              "[Family.ParentProfileRepository] Validation error creating parent profile",
              identity_id: attrs[:identity_id],
              errors: inspect(changeset.errors)
            )

            {:error, changeset}
          end
      end
    end
  end

  @impl true
  @doc """
  Retrieves a parent profile by identity ID from the database.

  Returns:
  - `{:ok, ParentProfile.t()}` when parent profile is found
  - `{:error, :not_found}` when no parent profile exists with the given identity_id
  """
  def get_by_identity_id(identity_id) when is_binary(identity_id) do
    db_interaction operation: :get_by_identity_id, entity: "parent_profile" do
      case Repo.one(from p in ParentProfileSchema, where: p.identity_id == ^identity_id) do
        nil -> {:error, :not_found}
        schema -> {:ok, ParentProfileMapper.to_domain(schema)}
      end
    end
  end

  @impl true
  @doc """
  Checks if a parent profile exists for the given identity ID.

  Returns boolean directly.
  """
  def has_profile?(identity_id) when is_binary(identity_id) do
    db_interaction operation: :has_profile, entity: "parent_profile" do
      ParentProfileSchema
      |> where([p], p.identity_id == ^identity_id)
      |> Repo.exists?()
    end
  end

  @impl true
  @doc """
  Retrieves multiple parent profiles by their IDs from the database.

  Missing or invalid IDs are silently excluded from the result.
  """
  def list_by_ids([]), do: []

  def list_by_ids(parent_ids) when is_list(parent_ids) do
    db_interaction operation: :list_by_ids, entity: "parent_profile" do
      ParentProfileSchema
      |> where([p], p.id in ^parent_ids)
      |> Repo.all()
      |> MapperHelpers.to_domain_list(ParentProfileMapper)
    end
  end
end
