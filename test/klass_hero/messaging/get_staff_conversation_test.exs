defmodule KlassHero.Messaging.GetStaffConversationTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Accounts.Scope
  alias KlassHero.AccountsFixtures
  alias KlassHero.Messaging
  alias KlassHero.Messaging.GetStaffConversation
  alias KlassHero.Messaging.Participant
  alias KlassHero.ProviderFixtures

  defp business do
    owner = AccountsFixtures.user_fixture(name: "Olive Owner", intended_roles: [:provider])
    provider = ProviderFixtures.provider_profile_fixture(identity_id: owner.id)

    staff_user = AccountsFixtures.user_fixture(name: "Sam Staff", intended_roles: [:staff])

    staff =
      ProviderFixtures.staff_member_fixture(provider_id: provider.id, user_id: staff_user.id)

    parent = AccountsFixtures.user_fixture(name: "Pat Parent")

    %{
      owner: owner,
      provider: provider,
      staff: staff,
      staff_user: staff_user,
      parent: parent,
      scope: %Scope{user: owner, provider: provider}
    }
  end

  defp staff_thread(ctx) do
    conversation = insert(:conversation_schema, provider_id: ctx.provider.id)

    insert(:participant_schema, conversation_id: conversation.id, user_id: ctx.staff_user.id)
    insert(:participant_schema, conversation_id: conversation.id, user_id: ctx.parent.id)

    {:ok, _} =
      Messaging.create_message(%{
        conversation_id: conversation.id,
        sender_id: ctx.parent.id,
        content: "Is pickup still at four?"
      })

    conversation
  end

  setup do
    business()
  end

  describe "execute/3 authorization" do
    test "refuses a staff scope of the very provider that owns the thread", ctx do
      conversation = staff_thread(ctx)

      assert {:error, :unauthorized} =
               GetStaffConversation.execute(
                 %Scope{user: ctx.staff_user, staff_member: ctx.staff},
                 conversation.id
               )
    end

    test "refuses a scope with no provider profile", ctx do
      conversation = staff_thread(ctx)

      assert {:error, :unauthorized} =
               GetStaffConversation.execute(
                 AccountsFixtures.user_scope_fixture(),
                 conversation.id
               )
    end

    # Owner authorization proves the scope owns *a* provider, never that it owns *this*
    # conversation — unlike `is_admin`, which grants blanket visibility. Both answers
    # must be identical, or a UUID becomes an oracle for another business's threads.
    test "a different provider's owner cannot tell a real thread from a missing one", ctx do
      conversation = staff_thread(ctx)

      stranger = business()

      assert GetStaffConversation.execute(stranger.scope, conversation.id) ==
               GetStaffConversation.execute(stranger.scope, Ecto.UUID.generate())

      assert {:error, :not_found} = GetStaffConversation.execute(stranger.scope, conversation.id)
    end
  end

  describe "execute/3 reading" do
    test "returns the thread with its messages and sender names", ctx do
      conversation = staff_thread(ctx)

      assert {:ok, result} = GetStaffConversation.execute(ctx.scope, conversation.id)
      assert result.conversation.id == conversation.id
      assert [message] = result.messages
      assert message.content == "Is pickup still at four?"
      assert result.sender_names[ctx.parent.id] == "Pat Parent"
      refute result.has_more
    end
  end

  describe "execute/3 is strictly read-only" do
    test "seats no participant for the owner", ctx do
      conversation = staff_thread(ctx)

      assert {:ok, _} = GetStaffConversation.execute(ctx.scope, conversation.id)

      refute Messaging.participant?(conversation.id, ctx.owner.id)

      assert Repo.aggregate(
               from(p in Participant, where: p.conversation_id == ^conversation.id),
               :count
             ) == 2
    end

    test "moves nobody's read receipt", ctx do
      conversation = staff_thread(ctx)

      # Stamped first, on purpose. Left at their initial `nil` the assertion would
      # still catch a mark-as-read — a DateTime is not nil — but nothing else: code
      # that *cleared* an existing receipt would compare `[nil, nil] == [nil, nil]`
      # and pass. A non-nil value pins the state in both directions.
      read_at = ~U[2026-01-01 09:00:00.000000Z]

      {1, _} =
        Repo.update_all(
          from(p in Participant,
            where: p.conversation_id == ^conversation.id and p.user_id == ^ctx.parent.id
          ),
          set: [last_read_at: read_at]
        )

      before =
        Repo.all(from(p in Participant, where: p.conversation_id == ^conversation.id))
        |> Enum.map(& &1.last_read_at)

      assert read_at in before

      assert {:ok, _} = GetStaffConversation.execute(ctx.scope, conversation.id)

      after_read =
        Repo.all(from(p in Participant, where: p.conversation_id == ^conversation.id))
        |> Enum.map(& &1.last_read_at)

      assert before == after_read
    end
  end

  # The mirror of `get_monitored_conversation_test.exs`'s "the write path gained no
  # admin branch". Read-only here is structural: there is no owner clause in
  # SendMessage to bypass, and this test is what keeps it that way.
  describe "the write path gained no owner branch" do
    test "an owner who is not a participant still cannot send a message", ctx do
      conversation = staff_thread(ctx)

      assert {:error, :not_participant} =
               Messaging.send_message(conversation.id, ctx.owner.id, "Let me step in here")
    end
  end
end
