defmodule KlassHero.Messaging.Adapters.Driven.Persistence.Mappers.ConversationMapperTest do
  @moduledoc """
  Unit tests for ConversationMapper.

  Covers schema-to-domain conversion, including association preload guards
  (Ecto.Association.NotLoaded → []) and atom/string type conversions.
  No database required — schemas are constructed inline.
  """

  use ExUnit.Case, async: true

  alias KlassHero.Messaging.Adapters.Driven.Persistence.Mappers.ConversationMapper
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.ConversationSchema
  alias KlassHero.Messaging.Domain.Models.Conversation
  alias KlassHero.Messaging.Participant

  @provider_id Ecto.UUID.generate()
  @program_id Ecto.UUID.generate()

  defp valid_schema(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      type: "direct",
      provider_id: @provider_id,
      program_id: nil,
      subject: nil,
      archived_at: nil,
      retention_until: nil,
      lock_version: 1,
      inserted_at: ~U[2025-03-01 10:00:00Z],
      updated_at: ~U[2025-03-01 10:00:00Z],
      participants: %Ecto.Association.NotLoaded{
        __field__: :participants,
        __owner__: ConversationSchema
      },
      messages: %Ecto.Association.NotLoaded{__field__: :messages, __owner__: ConversationSchema}
    }

    struct!(ConversationSchema, Map.merge(defaults, overrides))
  end

  defp participant_schema(overrides) do
    defaults = %{
      id: Ecto.UUID.generate(),
      conversation_id: Ecto.UUID.generate(),
      user_id: Ecto.UUID.generate(),
      last_read_at: nil,
      joined_at: ~U[2025-03-01 10:00:00Z],
      left_at: nil,
      inserted_at: ~U[2025-03-01 10:00:00Z],
      updated_at: ~U[2025-03-01 10:00:00Z]
    }

    struct!(Participant, Map.merge(defaults, overrides))
  end

  describe "to_domain/1" do
    test "converts all fields from schema to domain struct" do
      schema = valid_schema(%{participants: [], messages: []})

      conv = ConversationMapper.to_domain(schema)

      assert %Conversation{} = conv
      assert conv.id == schema.id
      assert conv.provider_id == @provider_id
      assert conv.program_id == nil
      assert conv.subject == nil
      assert conv.archived_at == nil
      assert conv.retention_until == nil
      assert conv.lock_version == 1
      assert conv.inserted_at == ~U[2025-03-01 10:00:00Z]
      assert conv.updated_at == ~U[2025-03-01 10:00:00Z]
    end

    test "converts type string to existing atom" do
      direct_schema = valid_schema(%{type: "direct", participants: [], messages: []})
      broadcast_schema = valid_schema(%{type: "program_broadcast", participants: [], messages: []})

      assert ConversationMapper.to_domain(direct_schema).type == :direct
      assert ConversationMapper.to_domain(broadcast_schema).type == :program_broadcast
    end

    test "maps Ecto.Association.NotLoaded participants to empty list" do
      schema = valid_schema()

      conv = ConversationMapper.to_domain(schema)

      assert conv.participants == []
    end

    test "maps Ecto.Association.NotLoaded messages to empty list" do
      schema = valid_schema()

      conv = ConversationMapper.to_domain(schema)

      assert conv.messages == []
    end

    test "maps loaded participants via ParticipantMapper" do
      conv_id = Ecto.UUID.generate()
      p = participant_schema(%{conversation_id: conv_id})
      schema = valid_schema(%{id: conv_id, participants: [p], messages: []})

      conv = ConversationMapper.to_domain(schema)

      assert [%Participant{}] = conv.participants
      assert hd(conv.participants).id == p.id
      assert hd(conv.participants).conversation_id == conv_id
    end

    test "maps program_id and subject for broadcast conversations" do
      schema =
        valid_schema(%{
          type: "program_broadcast",
          program_id: @program_id,
          subject: "Weekly Update",
          participants: [],
          messages: []
        })

      conv = ConversationMapper.to_domain(schema)

      assert conv.type == :program_broadcast
      assert conv.program_id == @program_id
      assert conv.subject == "Weekly Update"
    end

    test "preserves archived_at and retention_until when set" do
      now = ~U[2025-06-15 08:00:00Z]
      retention = ~U[2025-07-15 08:00:00Z]

      schema =
        valid_schema(%{
          archived_at: now,
          retention_until: retention,
          participants: [],
          messages: []
        })

      conv = ConversationMapper.to_domain(schema)

      assert conv.archived_at == now
      assert conv.retention_until == retention
    end
  end

  describe "to_schema_attrs/1" do
    test "converts domain struct to schema attribute map" do
      conv = %Conversation{
        id: Ecto.UUID.generate(),
        type: :direct,
        provider_id: @provider_id,
        program_id: nil,
        subject: nil,
        archived_at: nil,
        retention_until: nil,
        lock_version: 1
      }

      attrs = ConversationMapper.to_schema_attrs(conv)

      assert attrs.id == conv.id
      assert attrs.type == "direct"
      assert attrs.provider_id == @provider_id
      assert attrs.program_id == nil
      assert attrs.lock_version == 1
    end

    test "converts atom type to string" do
      conv = %Conversation{
        id: Ecto.UUID.generate(),
        type: :program_broadcast,
        provider_id: @provider_id,
        program_id: @program_id
      }

      attrs = ConversationMapper.to_schema_attrs(conv)

      assert attrs.type == "program_broadcast"
    end
  end

  describe "to_create_attrs/1" do
    test "takes only permitted keys" do
      attrs = %{
        type: :direct,
        provider_id: @provider_id,
        program_id: nil,
        subject: "hello",
        lock_version: 1,
        extra_field: "ignored"
      }

      result = ConversationMapper.to_create_attrs(attrs)

      assert Map.has_key?(result, :type)
      assert Map.has_key?(result, :provider_id)
      assert Map.has_key?(result, :program_id)
      assert Map.has_key?(result, :subject)
      refute Map.has_key?(result, :extra_field)
      refute Map.has_key?(result, :lock_version)
    end

    test "converts atom type to string" do
      attrs = %{type: :direct, provider_id: @provider_id}

      result = ConversationMapper.to_create_attrs(attrs)

      assert result.type == "direct"
    end

    test "leaves string type unchanged" do
      attrs = %{type: "direct", provider_id: @provider_id}

      result = ConversationMapper.to_create_attrs(attrs)

      assert result.type == "direct"
    end

    test "leaves nil type as nil" do
      attrs = %{type: nil, provider_id: @provider_id}

      result = ConversationMapper.to_create_attrs(attrs)

      assert result.type == nil
    end
  end
end
