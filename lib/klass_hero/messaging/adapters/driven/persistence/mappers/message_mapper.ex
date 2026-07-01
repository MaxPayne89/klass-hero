defmodule KlassHero.Messaging.Adapters.Driven.Persistence.Mappers.MessageMapper do
  @moduledoc """
  Maps between MessageSchema (Ecto) and Message (domain model).
  """

  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.MessageSchema
  alias KlassHero.Messaging.Domain.Models.Message

  @doc """
  Converts a MessageSchema to a domain Message.
  """
  @spec to_domain(MessageSchema.t()) :: Message.t()
  def to_domain(%MessageSchema{} = schema) do
    %Message{
      id: schema.id,
      conversation_id: schema.conversation_id,
      sender_id: schema.sender_id,
      content: schema.content,
      message_type: String.to_existing_atom(schema.message_type),
      deleted_at: schema.deleted_at,
      inserted_at: schema.inserted_at,
      updated_at: schema.updated_at,
      attachments: map_attachments(schema.attachments)
    }
  end

  # schema.attachments is already loaded as [%Attachment{}] (the schema-as-struct module
  # is the domain struct), so no per-element mapping is needed.
  defp map_attachments(%Ecto.Association.NotLoaded{}), do: []
  defp map_attachments(nil), do: []
  defp map_attachments(attachments), do: attachments

  @doc """
  Converts a domain Message to attributes for schema creation.
  """
  @spec to_schema_attrs(Message.t()) :: map()
  def to_schema_attrs(%Message{} = message) do
    %{
      id: message.id,
      conversation_id: message.conversation_id,
      sender_id: message.sender_id,
      content: message.content,
      message_type: to_string(message.message_type),
      deleted_at: message.deleted_at
    }
  end

  @doc """
  Converts creation attributes to schema-compatible format.
  """
  @spec to_create_attrs(map()) :: map()
  def to_create_attrs(attrs) when is_map(attrs) do
    attrs
    |> Map.take([:conversation_id, :sender_id, :content, :message_type])
    |> Map.update(:message_type, "text", fn
      nil -> "text"
      type when is_atom(type) -> to_string(type)
      type -> type
    end)
  end

  @doc """
  Builds a sender_names map from schemas with preloaded senders.

  Returns map of sender_id => display_name.
  Schemas with unloaded or nil senders are skipped.
  """
  @spec build_sender_names_map([MessageSchema.t()]) :: %{String.t() => String.t()}
  def build_sender_names_map(schemas) do
    schemas
    |> Enum.reject(fn schema ->
      match?(%Ecto.Association.NotLoaded{}, schema.sender) or is_nil(schema.sender)
    end)
    |> Map.new(fn schema -> {schema.sender_id, schema.sender.name} end)
  end
end
