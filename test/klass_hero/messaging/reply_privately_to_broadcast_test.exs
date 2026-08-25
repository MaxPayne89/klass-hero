defmodule KlassHero.Messaging.ReplyPrivatelyToBroadcastTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Accounts.Scope
  alias KlassHero.AccountsFixtures
  alias KlassHero.Family.ParentProfile
  alias KlassHero.Messaging.ReplyPrivatelyToBroadcast
  alias KlassHero.ProviderFixtures

  describe "execute/2" do
    setup do
      # Create provider with known user
      provider_user = AccountsFixtures.user_fixture()
      provider = insert(:provider_profile_schema, identity_id: provider_user.id)
      program = insert(:program_schema)

      # Create broadcast conversation
      broadcast =
        insert(:conversation_schema,
          type: "program_broadcast",
          provider_id: provider.id,
          program_id: program.id,
          subject: "Schedule Change"
        )

      # Create parent with scope
      parent_user = AccountsFixtures.user_fixture()

      insert(:participant_schema,
        conversation_id: broadcast.id,
        user_id: parent_user.id
      )

      parent_profile = %ParentProfile{
        id: Ecto.UUID.generate(),
        identity_id: parent_user.id
      }

      scope = %Scope{
        user: parent_user,
        roles: [:parent],
        parent: parent_profile,
        provider: nil
      }

      %{
        scope: scope,
        broadcast: broadcast,
        provider: provider,
        provider_user: provider_user,
        parent_user: parent_user
      }
    end

    test "creates direct conversation with provider and inserts system note", ctx do
      assert {:ok, direct_conversation_id} =
               ReplyPrivatelyToBroadcast.execute(ctx.scope, ctx.broadcast.id)

      assert {:ok, _conversation} = KlassHero.Messaging.get_conversation_by_id(direct_conversation_id)
      refute direct_conversation_id == ctx.broadcast.id

      # Verify system note was inserted
      {:ok, messages, _} =
        KlassHero.Messaging.list_messages_for_conversation(direct_conversation_id, limit: 10)

      system_messages = Enum.filter(messages, &(&1.message_type == :system))
      assert length(system_messages) == 1

      note = hd(system_messages)
      assert note.content =~ "[broadcast:#{ctx.broadcast.id}]"
      assert note.content =~ "Schedule Change"
    end

    test "reuses existing direct conversation", ctx do
      assert {:ok, first_id} =
               ReplyPrivatelyToBroadcast.execute(ctx.scope, ctx.broadcast.id)

      assert {:ok, second_id} =
               ReplyPrivatelyToBroadcast.execute(ctx.scope, ctx.broadcast.id)

      assert first_id == second_id
    end

    test "is idempotent — no duplicate system notes on repeated calls", ctx do
      {:ok, conversation_id} =
        ReplyPrivatelyToBroadcast.execute(ctx.scope, ctx.broadcast.id)

      {:ok, ^conversation_id} =
        ReplyPrivatelyToBroadcast.execute(ctx.scope, ctx.broadcast.id)

      {:ok, messages, _} =
        KlassHero.Messaging.list_messages_for_conversation(conversation_id, limit: 50)

      system_messages = Enum.filter(messages, &(&1.message_type == :system))
      assert length(system_messages) == 1
    end

    test "works for any parent", ctx do
      assert {:ok, _conversation_id} =
               ReplyPrivatelyToBroadcast.execute(ctx.scope, ctx.broadcast.id)
    end

    test "returns not_found for non-existent broadcast", ctx do
      assert {:error, :not_found} =
               ReplyPrivatelyToBroadcast.execute(ctx.scope, Ecto.UUID.generate())
    end

    test "returns error when conversation is not a broadcast (direct conversation)", ctx do
      # Guards against crafted calls targeting a direct conversation ID
      direct =
        insert(:conversation_schema,
          type: "direct",
          provider_id: ctx.provider.id
        )

      assert {:error, :not_broadcast} =
               ReplyPrivatelyToBroadcast.execute(ctx.scope, direct.id)
    end

    test "dedup works with more than 100 messages in the conversation (regression #431)", ctx do
      # First call creates the direct conversation and system note
      {:ok, conversation_id} =
        ReplyPrivatelyToBroadcast.execute(ctx.scope, ctx.broadcast.id)

      # Insert 110 regular messages to push the system note beyond the old 100-message ceiling
      for i <- 1..110 do
        insert(:message_schema,
          conversation_id: conversation_id,
          sender_id: ctx.parent_user.id,
          content: "Message #{i}",
          message_type: "text"
        )
      end

      # Second call should still detect the existing system note (no duplicate)
      {:ok, ^conversation_id} =
        ReplyPrivatelyToBroadcast.execute(ctx.scope, ctx.broadcast.id)

      {:ok, messages, _} =
        KlassHero.Messaging.list_messages_for_conversation(conversation_id, limit: 200)

      system_messages = Enum.filter(messages, &(&1.message_type == :system))
      assert length(system_messages) == 1
    end

    test "returns error when user is not a participant of the broadcast", ctx do
      non_participant_user = AccountsFixtures.user_fixture()

      non_participant_scope = %Scope{
        user: non_participant_user,
        roles: [:parent],
        parent: %ParentProfile{
          id: Ecto.UUID.generate(),
          identity_id: non_participant_user.id
        },
        provider: nil
      }

      assert {:error, :not_participant} =
               ReplyPrivatelyToBroadcast.execute(non_participant_scope, ctx.broadcast.id)
    end
  end

  describe "execute/2 — staff auto-inclusion" do
    setup do
      provider_user = AccountsFixtures.user_fixture()
      provider = insert(:provider_profile_schema, identity_id: provider_user.id)
      program = insert(:program_schema, provider_id: provider.id)

      broadcast =
        insert(:conversation_schema,
          type: "program_broadcast",
          provider_id: provider.id,
          program_id: program.id,
          subject: "Schedule Change"
        )

      parent_user = AccountsFixtures.user_fixture()

      insert(:participant_schema,
        conversation_id: broadcast.id,
        user_id: parent_user.id
      )

      parent_profile = %ParentProfile{
        id: Ecto.UUID.generate(),
        identity_id: parent_user.id
      }

      scope = %Scope{
        user: parent_user,
        roles: [:parent],
        parent: parent_profile,
        provider: nil
      }

      %{
        scope: scope,
        broadcast: broadcast,
        provider: provider,
        provider_user: provider_user,
        program: program,
        parent_user: parent_user
      }
    end

    test "adds assigned staff as participants when broadcast has program context", ctx do
      staff_user = AccountsFixtures.user_fixture()

      ProviderFixtures.assign_active_staff(%{
        provider_id: ctx.provider.id,
        program_id: ctx.program.id,
        staff_user_id: staff_user.id
      })

      assert {:ok, direct_conversation_id} =
               ReplyPrivatelyToBroadcast.execute(ctx.scope, ctx.broadcast.id)

      assert KlassHero.Messaging.participant?(direct_conversation_id, staff_user.id)
    end

    test "sets program_id on the new direct conversation", ctx do
      assert {:ok, direct_conversation_id} =
               ReplyPrivatelyToBroadcast.execute(ctx.scope, ctx.broadcast.id)

      assert {:ok, conversation} = KlassHero.Messaging.get_conversation_by_id(direct_conversation_id)
      assert conversation.program_id == ctx.program.id
    end

    test "does not error when provider owner is also assigned as program staff", ctx do
      ProviderFixtures.assign_active_staff(%{
        provider_id: ctx.provider.id,
        program_id: ctx.program.id,
        staff_user_id: ctx.provider_user.id
      })

      assert {:ok, direct_conversation_id} =
               ReplyPrivatelyToBroadcast.execute(ctx.scope, ctx.broadcast.id)

      assert KlassHero.Messaging.participant?(direct_conversation_id, ctx.provider_user.id)
    end

    test "does not retroactively add staff to a reused direct conversation", ctx do
      assert {:ok, first_id} =
               ReplyPrivatelyToBroadcast.execute(ctx.scope, ctx.broadcast.id)

      staff_user = AccountsFixtures.user_fixture()

      ProviderFixtures.assign_active_staff(%{
        provider_id: ctx.provider.id,
        program_id: ctx.program.id,
        staff_user_id: staff_user.id
      })

      assert {:ok, ^first_id} =
               ReplyPrivatelyToBroadcast.execute(ctx.scope, ctx.broadcast.id)

      refute KlassHero.Messaging.participant?(first_id, staff_user.id)
    end
  end
end
