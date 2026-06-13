defmodule KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.InboundEmailRepository do
  @moduledoc """
  Ecto-based repository for managing inbound emails.

  Implements ForManagingInboundEmails (writes) and ForQueryingInboundEmails (reads) ports.
  """

  @behaviour KlassHero.Messaging.Domain.Ports.ForManagingInboundEmails
  @behaviour KlassHero.Messaging.Domain.Ports.ForQueryingInboundEmails

  use KlassHero.Shared.Tracing

  alias KlassHero.Messaging.Adapters.Driven.Persistence.Mappers.InboundEmailMapper
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Queries.InboundEmailQueries
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.InboundEmailSchema
  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.RepositoryHelpers

  require Logger

  @impl true
  def create(attrs) do
    span do
      set_attributes("db", operation: "insert", entity: "inbound_email")

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
    span do
      set_attributes("db", operation: "select", entity: "inbound_email")

      InboundEmailQueries.base()
      |> InboundEmailQueries.by_id(id)
      |> RepositoryHelpers.fetch_one(InboundEmailMapper)
    end
  end

  @impl true
  def get_by_resend_id(resend_id) do
    span do
      set_attributes("db", operation: "select", entity: "inbound_email")

      InboundEmailQueries.base()
      |> InboundEmailQueries.by_resend_id(resend_id)
      |> RepositoryHelpers.fetch_one(InboundEmailMapper)
    end
  end

  @impl true
  def list(opts \\ []) do
    span do
      set_attributes("db", operation: "select", entity: "inbound_email")

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
    span do
      set_attributes("db", operation: "update", entity: "inbound_email")

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
    span do
      set_attributes("db", operation: "update", entity: "inbound_email")

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
    span do
      set_attributes("db", operation: "select", entity: "inbound_email")

      InboundEmailQueries.count_by_status(status)
      |> Repo.one()
      |> Kernel.||(0)
    end
  end
end
