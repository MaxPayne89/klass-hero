defmodule KlassHero.Messaging.Adapters.Driven.Persistence.Mappers.ConversationMapper do
  @moduledoc """
  Maps between ConversationSchema (Ecto) and Conversation (domain model).
  """

  alias KlassHero.Messaging.Adapters.Driven.Persistence.Mappers.MessageMapper
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.ConversationSchema
  alias KlassHero.Messaging.Domain.Models.Conversation

  @doc """
  Converts a ConversationSchema to a domain Conversation.
  """
  @spec to_domain(ConversationSchema.t()) :: Conversation.t()
  def to_domain(%ConversationSchema{} = schema) do
    # schema.participants is already loaded as [%Participant{}] (the schema-as-struct
    # module is the domain struct), so no per-element mapping is needed.
    participants =
      case schema.participants do
        %Ecto.Association.NotLoaded{} -> []
        participants -> participants
      end

    messages =
      case schema.messages do
        %Ecto.Association.NotLoaded{} -> []
        messages -> Enum.map(messages, &MessageMapper.to_domain/1)
      end

    %Conversation{
      id: schema.id,
      type: String.to_existing_atom(schema.type),
      provider_id: schema.provider_id,
      program_id: schema.program_id,
      subject: schema.subject,
      archived_at: schema.archived_at,
      retention_until: schema.retention_until,
      lock_version: schema.lock_version,
      inserted_at: schema.inserted_at,
      updated_at: schema.updated_at,
      participants: participants,
      messages: messages
    }
  end

  @doc """
  Converts a domain Conversation to attributes for schema creation.
  """
  @spec to_schema_attrs(Conversation.t()) :: map()
  def to_schema_attrs(%Conversation{} = conversation) do
    %{
      id: conversation.id,
      type: to_string(conversation.type),
      provider_id: conversation.provider_id,
      program_id: conversation.program_id,
      subject: conversation.subject,
      archived_at: conversation.archived_at,
      retention_until: conversation.retention_until,
      lock_version: conversation.lock_version
    }
  end

  @doc """
  Converts creation attributes to schema-compatible format.
  """
  @spec to_create_attrs(map()) :: map()
  def to_create_attrs(attrs) when is_map(attrs) do
    attrs
    |> Map.take([:type, :provider_id, :program_id, :subject])
    |> Map.update(:type, nil, fn
      nil -> nil
      type when is_atom(type) -> to_string(type)
      type -> type
    end)
  end
end
