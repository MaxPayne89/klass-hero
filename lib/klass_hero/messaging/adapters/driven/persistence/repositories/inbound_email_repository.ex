defmodule KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.InboundEmailRepository do
  @moduledoc """
  Ecto-based repository for managing inbound emails.

  Implements ForManagingInboundEmails (writes) and ForQueryingInboundEmails (reads) ports.
  """

  @behaviour KlassHero.Messaging.Domain.Ports.ForManagingInboundEmails
  @behaviour KlassHero.Messaging.Domain.Ports.ForQueryingInboundEmails

  use KlassHero.Shared.Interaction

  alias KlassHero.Messaging.Adapters.Driven.Persistence.Mappers.InboundEmailMapper
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Queries.InboundEmailQueries
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.InboundEmailSchema
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.RepositoryHelpers

  require Logger

  @impl true
  def create(attrs) do
    db_interaction operation: :create, entity: "inbound_email" do
      schema_attrs = InboundEmailMapper.to_create_attrs(attrs)

      %InboundEmailSchema{}
      |> InboundEmailSchema.create_changeset(schema_attrs)
      |> Repo.insert()
      |> case do
        {:ok, schema} ->
          email = InboundEmailMapper.to_domain(schema)

          Logger.info("Stored inbound email #{email.resend_id} from #{email.from_address}")

          {:ok, email}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @impl true
  def get_by_id(id) do
    db_interaction operation: :get_by_id, entity: "inbound_email" do
      InboundEmailQueries.base()
      |> InboundEmailQueries.by_id(id)
      |> RepositoryHelpers.fetch_one(InboundEmailMapper)
    end
  end

  @impl true
  def get_by_resend_id(resend_id) do
    db_interaction operation: :get_by_resend_id, entity: "inbound_email" do
      InboundEmailQueries.base()
      |> InboundEmailQueries.by_resend_id(resend_id)
      |> RepositoryHelpers.fetch_one(InboundEmailMapper)
    end
  end

  @impl true
  def list(opts \\ []) do
    db_interaction operation: :list, entity: "inbound_email" do
      limit = Keyword.get(opts, :limit, 50)
      status = Keyword.get(opts, :status)

      results =
        InboundEmailQueries.base()
        |> InboundEmailQueries.by_status(status)
        |> InboundEmailQueries.order_by_newest()
        |> InboundEmailQueries.paginate(opts)
        |> Repo.all()

      # Fetch limit+1 to detect next page without a separate COUNT query.
      has_more = length(results) > limit
      emails = results |> Enum.take(limit) |> Enum.map(&InboundEmailMapper.to_domain/1)

      {:ok, emails, has_more}
    end
  end

  @impl true
  def update_status(id, status, attrs) do
    db_interaction operation: :update_status, entity: "inbound_email" do
      InboundEmailSchema
      |> Repo.get(id)
      |> case do
        nil ->
          {:error, :not_found}

        schema ->
          update_attrs = Map.put(attrs, :status, status)

          schema
          |> InboundEmailSchema.status_changeset(update_attrs)
          |> Repo.update()
          |> case do
            {:ok, updated} ->
              Logger.debug("Updated inbound email status: #{id} -> #{status}")
              {:ok, InboundEmailMapper.to_domain(updated)}

            {:error, changeset} ->
              {:error, changeset}
          end
      end
    end
  end

  @impl true
  def update_content(id, attrs) do
    db_interaction operation: :update_content, entity: "inbound_email" do
      InboundEmailSchema
      |> Repo.get(id)
      |> case do
        nil ->
          {:error, :not_found}

        schema ->
          schema
          |> InboundEmailSchema.content_changeset(attrs)
          |> Repo.update()
          |> case do
            {:ok, updated} ->
              {:ok, InboundEmailMapper.to_domain(updated)}

            {:error, changeset} ->
              {:error, changeset}
          end
      end
    end
  end

  @impl true
  def count_by_status(status) do
    db_interaction operation: :count_by_status, entity: "inbound_email" do
      InboundEmailQueries.count_by_status(status)
      |> Repo.one()
      |> Kernel.||(0)
    end
  end
end
