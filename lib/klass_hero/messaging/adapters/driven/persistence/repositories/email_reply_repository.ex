defmodule KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.EmailReplyRepository do
  @moduledoc """
  Ecto-based repository for managing email replies.

  Implements ForManagingEmailReplies (writes) and ForQueryingEmailReplies (reads) ports.
  """

  @behaviour KlassHero.Messaging.Domain.Ports.ForManagingEmailReplies
  @behaviour KlassHero.Messaging.Domain.Ports.ForQueryingEmailReplies

  use KlassHero.Shared.Interaction

  alias KlassHero.Messaging.Adapters.Driven.Persistence.Mappers.EmailReplyMapper
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Queries.EmailReplyQueries
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.EmailReplySchema
  alias KlassHero.Repo

  require Logger

  @impl true
  def create(attrs) do
    db_interaction operation: :create, entity: "email_reply" do
      schema_attrs = EmailReplyMapper.to_create_attrs(attrs)

      %EmailReplySchema{}
      |> EmailReplySchema.create_changeset(schema_attrs)
      |> Repo.insert()
      |> case do
        {:ok, schema} ->
          reply = EmailReplyMapper.to_domain(schema)
          Logger.info("Created email reply #{reply.id} for email #{reply.inbound_email_id}")
          {:ok, reply}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @impl true
  def get_by_id(id) do
    db_interaction operation: :get_by_id, entity: "email_reply" do
      EmailReplyQueries.base()
      |> EmailReplyQueries.by_id(id)
      |> Repo.one()
      |> case do
        nil -> {:error, :not_found}
        schema -> {:ok, EmailReplyMapper.to_domain(schema)}
      end
    end
  end

  @impl true
  def update_status(id, status, attrs) do
    db_interaction operation: :update_status, entity: "email_reply" do
      EmailReplySchema
      |> Repo.get(id)
      |> case do
        nil ->
          {:error, :not_found}

        schema ->
          update_attrs = Map.put(attrs, :status, status)

          schema
          |> EmailReplySchema.status_changeset(update_attrs)
          |> Repo.update()
          |> case do
            {:ok, updated} ->
              Logger.debug("Updated email reply status: #{id} -> #{status}")
              {:ok, EmailReplyMapper.to_domain(updated)}

            {:error, changeset} ->
              {:error, changeset}
          end
      end
    end
  end

  @impl true
  def list_by_email(inbound_email_id) do
    db_interaction operation: :list_by_email, entity: "email_reply" do
      replies =
        EmailReplyQueries.base()
        |> EmailReplyQueries.by_email(inbound_email_id)
        |> EmailReplyQueries.order_by_oldest()
        |> Repo.all()
        |> Enum.map(&EmailReplyMapper.to_domain/1)

      {:ok, replies}
    end
  end
end
