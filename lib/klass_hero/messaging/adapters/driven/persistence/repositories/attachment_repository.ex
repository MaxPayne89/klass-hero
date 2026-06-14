defmodule KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.AttachmentRepository do
  @moduledoc """
  Ecto-based repository for managing message attachments.

  Implements ForManagingAttachments (writes) and ForQueryingAttachments (reads) ports.
  """

  @behaviour KlassHero.Messaging.Domain.Ports.ForManagingAttachments
  @behaviour KlassHero.Messaging.Domain.Ports.ForQueryingAttachments

  use KlassHero.Shared.Interaction

  import Ecto.Query

  alias KlassHero.Messaging.Adapters.Driven.Persistence.Mappers.AttachmentMapper
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.AttachmentSchema
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.MessageSchema
  alias KlassHero.Repo

  require Logger

  @impl true
  def create_many([]), do: {:ok, []}

  def create_many(attrs_list) do
    db_interaction operation: :create_many, entity: "attachment" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      entries =
        Enum.map(attrs_list, fn attrs ->
          attrs
          |> AttachmentMapper.to_create_attrs()
          |> Map.put(:id, Ecto.UUID.generate())
          |> Map.put(:inserted_at, now)
          |> Map.put(:updated_at, now)
        end)

      {count, schemas} = Repo.insert_all(AttachmentSchema, entries, returning: true)

      Logger.debug("Bulk-inserted attachments", count: count)

      {:ok, Enum.map(schemas, &AttachmentMapper.to_domain/1)}
    end
  rescue
    e in [Ecto.ConstraintError, Postgrex.Error] ->
      Logger.error("Failed to bulk-insert attachments",
        count: length(attrs_list),
        error: Exception.message(e)
      )

      {:error, :attachment_insert_failed}
  end

  @impl true
  def list_for_message(message_id) do
    db_interaction operation: :list_for_message, entity: "attachment" do
      AttachmentSchema
      |> where([a], a.message_id == ^message_id)
      |> order_by([a], asc: a.inserted_at)
      |> Repo.all()
      |> Enum.map(&AttachmentMapper.to_domain/1)
    end
  end

  @impl true
  def list_for_messages([]), do: %{}

  def list_for_messages(message_ids) do
    db_interaction operation: :list_for_messages, entity: "attachment" do
      AttachmentSchema
      |> where([a], a.message_id in ^message_ids)
      |> order_by([a], asc: a.inserted_at)
      |> Repo.all()
      |> Enum.map(&AttachmentMapper.to_domain/1)
      |> Enum.group_by(& &1.message_id)
    end
  end

  @impl true
  def get_storage_paths_for_conversations([]), do: {:ok, []}

  def get_storage_paths_for_conversations(conversation_ids) do
    db_interaction operation: :get_storage_paths_for_conversations, entity: "attachment" do
      paths =
        AttachmentSchema
        |> join(:inner, [a], m in MessageSchema, on: a.message_id == m.id)
        |> where([_a, m], m.conversation_id in ^conversation_ids)
        |> select([a, _m], a.storage_path)
        |> Repo.all()

      {:ok, paths}
    end
  end
end
