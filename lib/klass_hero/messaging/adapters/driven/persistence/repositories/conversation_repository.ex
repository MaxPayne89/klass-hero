defmodule KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.ConversationRepository do
  @moduledoc """
  Ecto-based repository for managing conversations.

  Implements ForManagingConversations (writes) and ForQueryingConversations (reads) ports.
  """

  @behaviour KlassHero.Messaging.Domain.Ports.ForManagingConversations
  @behaviour KlassHero.Messaging.Domain.Ports.ForQueryingConversations

  use KlassHero.Shared.Interaction

  import Ecto.Query

  alias KlassHero.Messaging.Adapters.Driven.Persistence.Mappers.ConversationMapper
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Queries.ConversationQueries
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.ConversationSchema
  alias KlassHero.Repo

  require Logger

  @impl true
  def create(attrs) do
    db_interaction operation: :create, entity: "conversation" do
      schema_attrs = ConversationMapper.to_create_attrs(attrs)

      %ConversationSchema{}
      |> ConversationSchema.create_changeset(schema_attrs)
      |> Repo.insert()
      |> case do
        {:ok, schema} ->
          conversation = ConversationMapper.to_domain(schema)

          Logger.debug("Created conversation",
            conversation_id: conversation.id,
            type: conversation.type
          )

          {:ok, conversation}

        {:error, %Ecto.Changeset{errors: errors}} = result ->
          if Keyword.has_key?(errors, :program_id) do
            {:error, :duplicate_broadcast}
          else
            result
          end
      end
    end
  end

  @impl true
  def get_by_id(id, opts \\ []) do
    db_interaction operation: :get_by_id, entity: "conversation" do
      preloads = Keyword.get(opts, :preload, [])

      ConversationQueries.base()
      |> ConversationQueries.by_id(id)
      |> ConversationQueries.preload_assocs(preloads)
      |> Repo.one()
      |> case do
        nil -> {:error, :not_found}
        schema -> {:ok, ConversationMapper.to_domain(schema)}
      end
    end
  end

  @impl true
  def find_direct_conversation(provider_id, user_id) do
    db_interaction operation: :find_direct_conversation, entity: "conversation" do
      ConversationQueries.find_direct(provider_id, user_id)
      |> Repo.one()
      |> case do
        nil -> {:error, :not_found}
        schema -> {:ok, ConversationMapper.to_domain(schema)}
      end
    end
  end

  @impl true
  def find_active_broadcast_for_program(provider_id, program_id) do
    db_interaction operation: :find_active_broadcast_for_program, entity: "conversation" do
      ConversationQueries.base()
      |> ConversationQueries.by_provider(provider_id)
      |> ConversationQueries.by_type(:program_broadcast)
      |> ConversationQueries.active_only()
      |> ConversationQueries.by_program(program_id)
      |> Repo.one()
      |> case do
        nil -> {:error, :not_found}
        schema -> {:ok, ConversationMapper.to_domain(schema)}
      end
    end
  end

  @impl true
  def list_for_user(user_id, opts \\ []) do
    db_interaction operation: :list_for_user, entity: "conversation" do
      limit = Keyword.get(opts, :limit, 50)

      results =
        ConversationQueries.base()
        |> ConversationQueries.active_only()
        |> ConversationQueries.where_user_is_participant(user_id)
        |> ConversationQueries.with_unread_count(user_id)
        |> ConversationQueries.order_by_recent_message()
        |> ConversationQueries.paginate(opts)
        |> Repo.all()

      has_more = length(results) > limit
      conversations = results |> Enum.take(limit) |> Enum.map(&ConversationMapper.to_domain/1)

      {:ok, conversations, has_more}
    end
  end

  @impl true
  def list_for_provider(provider_id, opts \\ []) do
    db_interaction operation: :list_for_provider, entity: "conversation" do
      limit = Keyword.get(opts, :limit, 50)
      type = Keyword.get(opts, :type)

      query =
        ConversationQueries.base()
        |> ConversationQueries.by_provider(provider_id)
        |> ConversationQueries.active_only()
        |> ConversationQueries.order_by_recent_message()
        |> ConversationQueries.paginate(opts)

      query = if type, do: ConversationQueries.by_type(query, type), else: query

      results = Repo.all(query)
      has_more = length(results) > limit
      conversations = results |> Enum.take(limit) |> Enum.map(&ConversationMapper.to_domain/1)

      {:ok, conversations, has_more}
    end
  end

  @impl true
  def archive(conversation) do
    db_interaction operation: :archive, entity: "conversation" do
      now = DateTime.utc_now()
      retention_until = DateTime.add(now, 30, :day)

      ConversationSchema
      |> Repo.get(conversation.id)
      |> case do
        nil ->
          {:error, :not_found}

        schema ->
          schema
          |> ConversationSchema.archive_changeset(%{
            archived_at: now,
            retention_until: retention_until
          })
          |> Repo.update()
          |> case do
            {:ok, updated} ->
              Logger.info("Archived conversation", conversation_id: conversation.id)
              {:ok, ConversationMapper.to_domain(updated)}

            error ->
              error
          end
      end
    end
  end

  @impl true
  def delete_expired(before) do
    db_interaction operation: :delete_expired, entity: "conversation" do
      {count, _} =
        ConversationQueries.base()
        |> ConversationQueries.archived_only()
        |> ConversationQueries.retention_expired(before)
        |> Repo.delete_all()

      Logger.info("Deleted expired conversations", count: count)
      {:ok, count}
    end
  end

  @impl true
  def archive_ended_program_conversations(cutoff_date, retention_days) do
    db_interaction operation: :archive_ended_program_conversations, entity: "conversation" do
      now = DateTime.utc_now()
      retention_until = DateTime.add(now, retention_days, :day)

      conversation_ids =
        ConversationQueries.base()
        |> ConversationQueries.with_ended_program(cutoff_date)
        |> ConversationQueries.select_ids()
        |> Repo.all()

      if conversation_ids == [] do
        {:ok, %{count: 0, conversation_ids: []}}
      else
        {count, _} =
          from(c in ConversationSchema, where: c.id in ^conversation_ids)
          |> Repo.update_all(set: [archived_at: now, retention_until: retention_until])

        Logger.info("Archived conversations for ended programs",
          count: count,
          cutoff_date: cutoff_date,
          retention_days: retention_days
        )

        {:ok, %{count: count, conversation_ids: conversation_ids}}
      end
    end
  end

  @impl true
  @spec get_total_unread_count(String.t()) :: non_neg_integer()
  def get_total_unread_count(user_id) do
    db_interaction operation: :get_total_unread_count, entity: "conversation" do
      case Repo.one(ConversationQueries.total_unread_count(user_id)) do
        nil -> 0
        count -> count
      end
    end
  end

  @impl true
  def list_active_program_conversation_ids_without_participant(program_id, user_id) do
    db_interaction operation: :list_active_program_conversation_ids_without_participant, entity: "conversation" do
      ConversationQueries.base()
      |> ConversationQueries.by_program(program_id)
      |> ConversationQueries.active_only()
      |> ConversationQueries.where_user_is_not_participant(user_id)
      |> ConversationQueries.select_ids()
      |> Repo.all()
    end
  end

  @impl true
  def list_active_program_conversation_ids_with_participant(program_id, user_id) do
    db_interaction operation: :list_active_program_conversation_ids_with_participant, entity: "conversation" do
      ConversationQueries.base()
      |> ConversationQueries.by_program(program_id)
      |> ConversationQueries.active_only()
      |> ConversationQueries.where_user_is_participant(user_id)
      |> ConversationQueries.select_ids()
      |> Repo.all()
    end
  end

  @impl true
  def list_expired_ids(before) do
    db_interaction operation: :list_expired_ids, entity: "conversation" do
      ConversationQueries.base()
      |> ConversationQueries.archived_only()
      |> ConversationQueries.retention_expired(before)
      |> ConversationQueries.select_ids()
      |> Repo.all()
    end
  end
end
