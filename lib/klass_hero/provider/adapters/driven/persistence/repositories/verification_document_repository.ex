defmodule KlassHero.Provider.Adapters.Driven.Persistence.Repositories.VerificationDocumentRepository do
  @moduledoc """
  Ecto-based repository for verification documents.

  Implements `ForStoringVerificationDocuments` and `ForQueryingVerificationDocuments`.
  Infrastructure errors are not caught — supervision tree handles them.
  """

  @behaviour KlassHero.Provider.Domain.Ports.ForQueryingVerificationDocuments
  @behaviour KlassHero.Provider.Domain.Ports.ForStoringVerificationDocuments

  use KlassHero.Shared.Tracing

  import Ecto.Query

  alias KlassHero.Provider.Adapters.Driven.Persistence.Mappers.VerificationDocumentMapper
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.ProviderProfileSchema
  alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.VerificationDocumentSchema
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.MapperHelpers
  alias KlassHero.Shared.Adapters.Driven.Persistence.RepositoryHelpers

  @impl true
  def create(document) do
    span do
      set_attributes("db", operation: "insert", entity: "verification_document")

      attrs = VerificationDocumentMapper.to_schema(document)

      with {:ok, schema} <-
             %VerificationDocumentSchema{}
             |> VerificationDocumentSchema.changeset(attrs)
             |> Repo.insert() do
        {:ok, VerificationDocumentMapper.to_domain(schema)}
      end
    end
  end

  @impl true
  def get(id) do
    span do
      set_attributes("db", operation: "select", entity: "verification_document")

      RepositoryHelpers.get_by_id(VerificationDocumentSchema, id, VerificationDocumentMapper)
    end
  end

  @impl true
  def get_by_provider(provider_id) do
    span do
      set_attributes("db", operation: "select", entity: "verification_document")

      docs =
        VerificationDocumentSchema
        |> where([d], d.provider_id == ^provider_id)
        |> order_by([d], desc: d.inserted_at)
        |> Repo.all()
        |> MapperHelpers.to_domain_list(VerificationDocumentMapper)

      {:ok, docs}
    end
  end

  @impl true
  def update(document) do
    span do
      set_attributes("db", operation: "update", entity: "verification_document")

      with {:ok, schema} <-
             RepositoryHelpers.get_schema_by_uuid(VerificationDocumentSchema, document.id),
           attrs = VerificationDocumentMapper.to_schema(document),
           {:ok, updated} <-
             schema |> VerificationDocumentSchema.changeset(attrs) |> Repo.update() do
        {:ok, VerificationDocumentMapper.to_domain(updated)}
      end
    end
  end

  @impl true
  def list_pending do
    span do
      set_attributes("db", operation: "select", entity: "verification_document")

      docs =
        VerificationDocumentSchema
        |> where([d], d.status == "pending")
        |> order_by([d], asc: d.inserted_at)
        |> Repo.all()
        |> MapperHelpers.to_domain_list(VerificationDocumentMapper)

      {:ok, docs}
    end
  end

  @impl true
  def list_by_status(status) when is_atom(status) do
    span do
      set_attributes("db", operation: "select", entity: "verification_document")

      status_string = Atom.to_string(status)

      docs =
        VerificationDocumentSchema
        |> where([d], d.status == ^status_string)
        |> order_by([d], desc: d.inserted_at)
        |> Repo.all()
        |> MapperHelpers.to_domain_list(VerificationDocumentMapper)

      {:ok, docs}
    end
  end

  # :pending orders oldest-first (FIFO); nil and other statuses order newest-first.
  @impl true
  def list_for_admin_review(status) when is_atom(status) or is_nil(status) do
    span do
      set_attributes("db", operation: "select", entity: "verification_document")

      query =
        case status do
          nil ->
            order_by(admin_review_base_query(), [d], desc: d.inserted_at)

          :pending ->
            admin_review_base_query()
            |> where([d], d.status == ^Atom.to_string(:pending))
            |> order_by([d], asc: d.inserted_at)

          status when is_atom(status) ->
            admin_review_base_query()
            |> where([d], d.status == ^Atom.to_string(status))
            |> order_by([d], desc: d.inserted_at)
        end

      results = query |> Repo.all() |> Enum.map(&to_admin_review_result/1)

      {:ok, results}
    end
  end

  @impl true
  def get_for_admin_review(id) do
    span do
      set_attributes("db", operation: "select", entity: "verification_document")

      query = where(admin_review_base_query(), [d], d.id == ^id)

      case Repo.one(query) do
        nil -> {:error, :not_found}
        result -> {:ok, to_admin_review_result(result)}
      end
    end
  end

  defp admin_review_base_query do
    from d in VerificationDocumentSchema,
      join: p in ProviderProfileSchema,
      on: d.provider_id == p.id,
      select: {d, p.business_name}
  end

  defp to_admin_review_result({schema, business_name}) do
    %{
      document: VerificationDocumentMapper.to_domain(schema),
      provider_business_name: business_name
    }
  end
end
