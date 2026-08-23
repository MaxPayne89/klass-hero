defmodule KlassHero.Messaging.ConversationTest do
  @moduledoc """
  Covers the flattened Conversation schema-as-struct: its changesets (the sole
  validation gatekeeper) plus persistence through the public `KlassHero.Messaging` API.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Messaging
  alias KlassHero.Messaging.Conversation

  describe "direct_attrs/2" do
    test "omits :program_id entirely when there is no program" do
      attrs = Conversation.direct_attrs("prov-1", nil)

      assert attrs == %{type: :direct, provider_id: "prov-1"}
      refute Map.has_key?(attrs, :program_id)
    end

    test "carries :program_id when the thread hangs off a program" do
      assert Conversation.direct_attrs("prov-1", "prog-9") ==
               %{type: :direct, provider_id: "prov-1", program_id: "prog-9"}
    end
  end

  describe "create_changeset/2" do
    test "valid for a direct conversation" do
      changeset =
        Conversation.create_changeset(%{type: :direct, provider_id: Ecto.UUID.generate()})

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :lock_version) == 1
    end

    test "valid for a program broadcast with a program_id" do
      changeset =
        Conversation.create_changeset(%{
          type: :program_broadcast,
          provider_id: Ecto.UUID.generate(),
          program_id: Ecto.UUID.generate()
        })

      assert changeset.valid?
    end

    test "requires type and provider_id" do
      changeset = Conversation.create_changeset(%{})

      assert %{type: ["can't be blank"], provider_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects a type outside the enum" do
      changeset =
        Conversation.create_changeset(%{type: :group_chat, provider_id: Ecto.UUID.generate()})

      assert %{type: ["is invalid"]} = errors_on(changeset)
    end

    test "requires program_id for program broadcasts" do
      changeset =
        Conversation.create_changeset(%{type: :program_broadcast, provider_id: Ecto.UUID.generate()})

      assert %{program_id: ["is required for program broadcasts"]} = errors_on(changeset)
    end

    test "rejects a subject longer than 500 characters" do
      changeset =
        Conversation.create_changeset(%{
          type: :direct,
          provider_id: Ecto.UUID.generate(),
          subject: String.duplicate("x", 501)
        })

      assert %{subject: ["should be at most 500 character(s)"]} = errors_on(changeset)
    end
  end

  describe "create_conversation/1" do
    test "persists a direct conversation" do
      provider = insert(:provider_profile_schema)

      assert {:ok, %Conversation{} = conversation} =
               Messaging.create_conversation(%{type: :direct, provider_id: provider.id})

      assert conversation.type == :direct
    end

    test "rewrites the broadcast-uniqueness violation to :duplicate_broadcast" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema)
      attrs = %{type: :program_broadcast, provider_id: provider.id, program_id: program.id}

      assert {:ok, _} = Messaging.create_conversation(attrs)
      assert {:error, :duplicate_broadcast} = Messaging.create_conversation(attrs)
    end
  end

  describe "get_conversation_by_id/2 and finders" do
    test "returns the conversation, or :not_found" do
      conversation = insert(:conversation_schema)

      assert {:ok, %Conversation{}} = Messaging.get_conversation_by_id(conversation.id)
      assert {:error, :not_found} = Messaging.get_conversation_by_id(Ecto.UUID.generate())
    end

    test "find_active_broadcast_for_program finds the active broadcast" do
      conversation = insert(:broadcast_conversation_schema)

      assert {:ok, found} =
               Messaging.find_active_broadcast_for_program(
                 conversation.provider_id,
                 conversation.program_id
               )

      assert found.id == conversation.id
    end
  end

  describe "delete_expired_conversations/1" do
    test "deletes archived conversations past their retention window" do
      conversation =
        insert(:conversation_schema,
          archived_at: DateTime.utc_now() |> DateTime.add(-31, :day) |> DateTime.truncate(:second),
          retention_until: DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)
        )

      future = DateTime.add(DateTime.utc_now(), 60, :day)

      assert {:ok, count} = Messaging.delete_expired_conversations(future)
      assert count >= 1
      assert {:error, :not_found} = Messaging.get_conversation_by_id(conversation.id)
    end
  end
end
