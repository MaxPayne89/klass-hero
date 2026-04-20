defmodule KlassHero.Messaging.Adapters.Driven.Persistence.Mappers.ParticipantMapperTest do
  @moduledoc """
  Unit tests for ParticipantMapper.

  Covers:
  - `to_domain/1`: full field mapping and nil optional passthrough
  - `to_schema_attrs/1`: selects the 6 writable fields; excludes inserted_at/updated_at
  - `to_create_attrs/1`: key filtering, default joined_at injection, and override preservation

  No database required — schemas and domain structs are constructed inline.
  """

  use ExUnit.Case, async: true

  alias KlassHero.Messaging.Adapters.Driven.Persistence.Mappers.ParticipantMapper
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.ParticipantSchema
  alias KlassHero.Messaging.Domain.Models.Participant

  @conversation_id Ecto.UUID.generate()
  @user_id Ecto.UUID.generate()
  @joined_at ~U[2025-06-01 10:00:00Z]
  @last_read_at ~U[2025-06-02 12:00:00Z]
  @left_at ~U[2025-06-03 14:00:00Z]
  @inserted_at ~U[2025-06-01 10:00:00Z]
  @updated_at ~U[2025-06-02 12:00:00Z]

  defp valid_schema(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      conversation_id: @conversation_id,
      user_id: @user_id,
      last_read_at: @last_read_at,
      joined_at: @joined_at,
      left_at: nil,
      inserted_at: @inserted_at,
      updated_at: @updated_at
    }

    struct!(ParticipantSchema, Map.merge(defaults, overrides))
  end

  defp valid_participant(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      conversation_id: @conversation_id,
      user_id: @user_id,
      last_read_at: @last_read_at,
      joined_at: @joined_at,
      left_at: nil,
      inserted_at: @inserted_at,
      updated_at: @updated_at
    }

    struct!(Participant, Map.merge(defaults, overrides))
  end

  describe "to_domain/1" do
    test "maps all fields from schema to domain struct" do
      schema = valid_schema(left_at: @left_at)

      participant = ParticipantMapper.to_domain(schema)

      assert %Participant{} = participant
      assert participant.id == schema.id
      assert participant.conversation_id == @conversation_id
      assert participant.user_id == @user_id
      assert participant.last_read_at == @last_read_at
      assert participant.joined_at == @joined_at
      assert participant.left_at == @left_at
      assert participant.inserted_at == @inserted_at
      assert participant.updated_at == @updated_at
    end

    test "nil optional fields pass through as nil" do
      schema = valid_schema(last_read_at: nil, left_at: nil)

      participant = ParticipantMapper.to_domain(schema)

      assert participant.last_read_at == nil
      assert participant.left_at == nil
    end
  end

  describe "to_schema_attrs/1" do
    test "extracts the six writable fields" do
      participant = valid_participant(left_at: @left_at)

      attrs = ParticipantMapper.to_schema_attrs(participant)

      assert attrs.id == participant.id
      assert attrs.conversation_id == @conversation_id
      assert attrs.user_id == @user_id
      assert attrs.last_read_at == @last_read_at
      assert attrs.joined_at == @joined_at
      assert attrs.left_at == @left_at
    end

    test "does not include inserted_at or updated_at" do
      participant = valid_participant()

      attrs = ParticipantMapper.to_schema_attrs(participant)

      refute Map.has_key?(attrs, :inserted_at)
      refute Map.has_key?(attrs, :updated_at)
    end

    test "nil optional fields are preserved in attrs" do
      participant = valid_participant(last_read_at: nil, left_at: nil)

      attrs = ParticipantMapper.to_schema_attrs(participant)

      assert attrs.last_read_at == nil
      assert attrs.left_at == nil
    end
  end

  describe "to_create_attrs/1" do
    test "retains conversation_id, user_id, joined_at, and last_read_at" do
      attrs = %{
        conversation_id: @conversation_id,
        user_id: @user_id,
        joined_at: @joined_at,
        last_read_at: @last_read_at
      }

      result = ParticipantMapper.to_create_attrs(attrs)

      assert result.conversation_id == @conversation_id
      assert result.user_id == @user_id
      assert result.joined_at == @joined_at
      assert result.last_read_at == @last_read_at
    end

    test "injects a default joined_at when not provided" do
      before_call = DateTime.utc_now()

      result = ParticipantMapper.to_create_attrs(%{conversation_id: @conversation_id, user_id: @user_id})

      after_call = DateTime.utc_now()

      assert %DateTime{} = result.joined_at
      assert DateTime.compare(result.joined_at, before_call) in [:gt, :eq]
      assert DateTime.compare(result.joined_at, after_call) in [:lt, :eq]
    end

    test "preserves provided joined_at and does not override it" do
      result = ParticipantMapper.to_create_attrs(%{conversation_id: @conversation_id, joined_at: @joined_at})

      assert result.joined_at == @joined_at
    end

    test "strips unrecognised keys" do
      attrs = %{
        conversation_id: @conversation_id,
        user_id: @user_id,
        joined_at: @joined_at,
        id: "should-be-stripped",
        left_at: @left_at,
        extra: "noise"
      }

      result = ParticipantMapper.to_create_attrs(attrs)

      refute Map.has_key?(result, :id)
      refute Map.has_key?(result, :left_at)
      refute Map.has_key?(result, :extra)
    end
  end
end
