defmodule KlassHero.Family.Adapters.Driven.Persistence.Repositories.ConsentRepository do
  @moduledoc """
  Repository implementation for consent persistence.

  Implements the ForStoringConsents port with:
  - Domain entity mapping via ConsentMapper
  - Idiomatic "let it crash" error handling

  Infrastructure errors (connection, query) are not caught - they crash and
  are handled by the supervision tree.
  """

  @behaviour KlassHero.Family.Domain.Ports.ForQueryingConsents
  @behaviour KlassHero.Family.Domain.Ports.ForStoringConsents

  use KlassHero.Shared.Interaction

  import Ecto.Query

  alias KlassHero.Family.Adapters.Driven.Persistence.Mappers.ConsentMapper
  alias KlassHero.Family.Adapters.Driven.Persistence.Schemas.ConsentSchema
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.EctoErrorHelpers
  alias KlassHero.Shared.Adapters.Driven.Persistence.MapperHelpers
  alias KlassHero.Shared.Adapters.Driven.Persistence.RepositoryHelpers
  alias KlassHero.Shared.ErrorIds

  @impl true
  def grant(attrs) when is_map(attrs) do
    db_interaction operation: :grant, entity: "consent" do
      changeset = ConsentSchema.changeset(%ConsentSchema{}, attrs)

      case Repo.insert(changeset) do
        {:ok, schema} ->
          {:ok, ConsentMapper.to_domain(schema)}

        {:error, %Ecto.Changeset{} = changeset} ->
          # Unique partial index on (child_id, consent_type) WHERE withdrawn_at IS NULL
          if EctoErrorHelpers.any_unique_constraint_violation?(changeset.errors) do
            {:error, :already_active}
          else
            RepositoryHelpers.log_validation_error(changeset, ErrorIds.consent_grant_failed())
            {:error, changeset}
          end
      end
    end
  end

  @impl true
  def withdraw(consent_id, %DateTime{} = withdrawn_at) when is_binary(consent_id) do
    db_interaction operation: :withdraw, entity: "consent" do
      case get_schema(consent_id) do
        {:ok, schema} ->
          changeset = ConsentSchema.withdraw_changeset(schema, withdrawn_at)

          case Repo.update(changeset) do
            {:ok, updated} ->
              {:ok, ConsentMapper.to_domain(updated)}

            {:error, changeset} ->
              RepositoryHelpers.log_validation_error(changeset, ErrorIds.consent_withdraw_failed())
              {:error, changeset}
          end

        {:error, :not_found} ->
          {:error, :not_found}
      end
    end
  end

  @impl true
  def get_active_for_child(child_id, consent_type) when is_binary(child_id) and is_binary(consent_type) do
    db_interaction operation: :get_active_for_child, entity: "consent" do
      ConsentSchema
      |> where([c], c.child_id == ^child_id)
      |> where([c], c.consent_type == ^consent_type)
      |> where([c], is_nil(c.withdrawn_at))
      |> limit(1)
      |> RepositoryHelpers.fetch_one(ConsentMapper)
    end
  end

  @impl true
  def list_active_by_child(child_id) when is_binary(child_id) do
    db_interaction operation: :list_active_by_child, entity: "consent" do
      ConsentSchema
      |> where([c], c.child_id == ^child_id)
      |> where([c], is_nil(c.withdrawn_at))
      |> order_by([c], asc: c.consent_type)
      |> Repo.all()
      |> MapperHelpers.to_domain_list(ConsentMapper)
    end
  end

  @impl true
  def list_active_for_children(child_ids, consent_type) when is_list(child_ids) and is_binary(consent_type) do
    db_interaction operation: :list_active_for_children, entity: "consent" do
      ConsentSchema
      |> where([c], c.child_id in ^child_ids)
      |> where([c], c.consent_type == ^consent_type)
      |> where([c], is_nil(c.withdrawn_at))
      |> Repo.all()
      |> MapperHelpers.to_domain_list(ConsentMapper)
    end
  end

  @impl true
  def list_all_by_child(child_id) when is_binary(child_id) do
    db_interaction operation: :list_all_by_child, entity: "consent" do
      ConsentSchema
      |> where([c], c.child_id == ^child_id)
      |> order_by([c], asc: c.consent_type, desc: c.granted_at)
      |> Repo.all()
      |> MapperHelpers.to_domain_list(ConsentMapper)
    end
  end

  @impl true
  def delete_all_for_child(child_id) when is_binary(child_id) do
    db_interaction operation: :delete_all_for_child, entity: "consent" do
      {count, _} =
        ConsentSchema
        |> where([c], c.child_id == ^child_id)
        |> Repo.delete_all()

      {:ok, count}
    end
  end

  defp get_schema(consent_id), do: RepositoryHelpers.get_schema_by_uuid(ConsentSchema, consent_id)
end
