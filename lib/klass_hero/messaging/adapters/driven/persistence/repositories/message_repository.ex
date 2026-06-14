defmodule KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.MessageRepository do
  @moduledoc """
  Ecto-based repository for managing messages.

  Implements ForManagingMessages (writes) and ForQueryingMessages (reads) ports.
  """

  @behaviour KlassHero.Messaging.Domain.Ports.ForManagingMessages
  @behaviour KlassHero.Messaging.Domain.Ports.ForQueryingMessages

  use KlassHero.Shared.Interaction

  import Ecto.Query

  alias KlassHero.Messaging.Adapters.Driven.Persistence.Mappers.MessageMapper
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Queries.MessageQueries

  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.{
    ConversationSchema,
    MessageSchema
  }

  alias KlassHero.Repo
  alias KlassHero.Shared.Adapters.Driven.Persistence.RepositoryHelpers

  require Logger

  @impl true
  def create(attrs) do
    db_interaction operation: :create, entity: "message" do
      schema_attrs = MessageMapper.to_create_attrs(attrs)

      %MessageSchema{}
      |> MessageSchema.create_changeset(schema_attrs)
      |> Repo.insert()
      |> case do
        {:ok, schema} ->
          message = MessageMapper.to_domain(schema)

          Logger.debug("Created message",
            message_id: message.id,
            conversation_id: message.conversation_id
          )

          {:ok, message}

        error ->
          error
      end
    end
  end

  @impl true
  def get_by_id(id) do
    db_interaction operation: :get_by_id, entity: "message" do
      MessageQueries.base()
      |> MessageQueries.by_id(id)
      |> RepositoryHelpers.fetch_one(MessageMapper)
    end
  end

  @impl true
  def list_for_conversation(conversation_id, opts \\ []) do
    db_interaction operation: :list_for_conversation, entity: "message" do
      limit = Keyword.get(opts, :limit, 50)

      results =
        MessageQueries.base()
        |> MessageQueries.by_conversation(conversation_id)
        |> MessageQueries.not_deleted()
        |> MessageQueries.order_by_newest()
        |> MessageQueries.paginate(opts)
        |> MessageQueries.preload_assocs([:attachments])
        |> Repo.all()

      has_more = length(results) > limit
      messages = results |> Enum.take(limit) |> Enum.map(&MessageMapper.to_domain/1)

      {:ok, messages, has_more}
    end
  end

  @impl true
  def list_with_senders(conversation_id, opts \\ []) do
    db_interaction operation: :list_with_senders, entity: "message" do
      limit = Keyword.get(opts, :limit, 50)

      results =
        MessageQueries.base()
        |> MessageQueries.by_conversation(conversation_id)
        |> MessageQueries.not_deleted()
        |> MessageQueries.order_by_newest()
        |> MessageQueries.paginate(opts)
        |> MessageQueries.preload_assocs([:sender, :attachments])
        |> Repo.all()

      has_more = length(results) > limit
      schemas = Enum.take(results, limit)

      sender_names = MessageMapper.build_sender_names_map(schemas)
      messages = Enum.map(schemas, &MessageMapper.to_domain/1)

      {:ok, messages, sender_names, has_more}
    end
  end

  @impl true
  def get_latest(conversation_id) do
    db_interaction operation: :get_latest, entity: "message" do
      MessageQueries.latest_for_conversation(conversation_id)
      |> Repo.one()
      |> case do
        nil -> {:error, :not_found}
        schema -> {:ok, MessageMapper.to_domain(schema)}
      end
    end
  end

  @impl true
  def soft_delete(message) do
    db_interaction operation: :soft_delete, entity: "message" do
      now = DateTime.utc_now()

      MessageSchema
      |> Repo.get(message.id)
      |> case do
        nil ->
          {:error, :not_found}

        schema ->
          schema
          |> MessageSchema.delete_changeset(%{deleted_at: now})
          |> Repo.update()
          |> case do
            {:ok, updated} ->
              Logger.info("Soft deleted message", message_id: message.id)
              {:ok, MessageMapper.to_domain(updated)}

            error ->
              error
          end
      end
    end
  end

  @impl true
  def count_unread(conversation_id, last_read_at) do
    db_interaction operation: :count_unread, entity: "message" do
      MessageQueries.count_unread(conversation_id, last_read_at)
      |> Repo.one()
      |> Kernel.||(0)
    end
  end

  @impl true
  def anonymize_for_sender(sender_id) do
    db_interaction operation: :anonymize_for_sender, entity: "message" do
      {count, _} =
        from(m in MessageSchema,
          where: m.sender_id == ^sender_id
        )
        |> Repo.update_all(set: [content: "[deleted]"])

      Logger.debug("Anonymized messages for sender",
        sender_id: sender_id,
        count: count
      )

      {:ok, count}
    end
  rescue
    e in DBConnection.ConnectionError ->
      Logger.error("Database connection error anonymizing messages for sender",
        sender_id: sender_id,
        error: Exception.message(e)
      )

      {:error, :database_connection_error}

    e in Postgrex.Error ->
      Logger.error("Database query error anonymizing messages for sender",
        sender_id: sender_id,
        error: Exception.message(e)
      )

      {:error, :database_query_error}
  end

  @impl true
  def delete_for_expired_conversations(before) do
    db_interaction operation: :delete_for_expired_conversations, entity: "message" do
      expired_conversation_ids =
        from(c in ConversationSchema,
          where: not is_nil(c.retention_until),
          where: c.retention_until < ^before,
          select: c.id
        )
        |> Repo.all()

      if expired_conversation_ids == [] do
        {:ok, 0, []}
      else
        {count, _} =
          from(m in MessageSchema,
            where: m.conversation_id in ^expired_conversation_ids
          )
          |> Repo.delete_all()

        Logger.info("Deleted messages for expired conversations",
          count: count,
          conversation_count: length(expired_conversation_ids)
        )

        {:ok, count, expired_conversation_ids}
      end
    end
  end
end
