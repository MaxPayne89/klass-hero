defmodule KlassHero.Messaging.ListStaffConversationsTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Accounts.Scope
  alias KlassHero.AccountsFixtures
  alias KlassHero.Messaging
  alias KlassHero.Messaging.ListStaffConversations
  alias KlassHero.Messaging.StaffConversation
  alias KlassHero.ProviderFixtures

  # An owner, a staffer they employ, and a parent — the cast every test here needs.
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

  defp staff_thread(ctx, attrs \\ []) do
    conversation =
      insert(:conversation_schema, Keyword.merge([provider_id: ctx.provider.id], attrs))

    insert(:participant_schema, conversation_id: conversation.id, user_id: ctx.staff_user.id)
    insert(:participant_schema, conversation_id: conversation.id, user_id: ctx.parent.id)

    conversation
  end

  defp say(conversation, sender, content) do
    {:ok, message} =
      Messaging.create_message(%{
        conversation_id: conversation.id,
        sender_id: sender.id,
        content: content
      })

    message
  end

  setup do
    business()
  end

  describe "execute/2 authorization" do
    test "refuses a staff scope of the very provider it works for", ctx do
      staff_thread(ctx)

      assert {:error, :unauthorized} =
               ListStaffConversations.execute(%Scope{
                 user: ctx.staff_user,
                 staff_member: ctx.staff
               })
    end

    test "refuses a scope with no provider profile, even when nothing exists to list" do
      assert {:error, :unauthorized} =
               ListStaffConversations.execute(AccountsFixtures.user_scope_fixture())
    end
  end

  describe "execute/2 listing" do
    test "lists a thread the owner's staff conducts without them", ctx do
      conversation = staff_thread(ctx)

      assert {:ok, [row], false} = ListStaffConversations.execute(ctx.scope)
      assert %StaffConversation{} = row
      assert row.conversation_id == conversation.id
      refute Messaging.participant?(conversation.id, ctx.owner.id)
    end

    # The one behavioural difference from MonitorConversations: the owner's own threads
    # already render as rich cards in their inbox, so listing them here would show them
    # twice across the two tabs.
    test "excludes a thread the owner is already a participant of", ctx do
      mine = staff_thread(ctx)
      insert(:participant_schema, conversation_id: mine.id, user_id: ctx.owner.id)

      theirs = staff_thread(ctx)

      assert {:ok, [row], false} = ListStaffConversations.execute(ctx.scope)
      assert row.conversation_id == theirs.id
    end

    test "excludes another provider's conversations", ctx do
      mine = staff_thread(ctx)
      insert(:conversation_schema)

      assert {:ok, [row], false} = ListStaffConversations.execute(ctx.scope)
      assert row.conversation_id == mine.id
    end

    test "excludes archived conversations", ctx do
      staff_thread(ctx, archived_at: DateTime.utc_now() |> DateTime.truncate(:second))

      assert {:ok, [], false} = ListStaffConversations.execute(ctx.scope)
    end
  end

  describe "execute/2 row contents" do
    test "names the non-staff party and the staff members in the thread", ctx do
      staff_thread(ctx)

      assert {:ok, [row], false} = ListStaffConversations.execute(ctx.scope)
      assert row.other_participant_name == "Pat Parent"
      assert row.staff_member_names == ["Sam Staff"]
    end

    test "carries the latest message and its timestamp", ctx do
      conversation = staff_thread(ctx)
      say(conversation, ctx.parent, "First")
      latest = say(conversation, ctx.staff_user, "Second")

      assert {:ok, [row], false} = ListStaffConversations.execute(ctx.scope)
      assert row.latest_message_content == "Second"
      assert row.latest_message_at == latest.inserted_at
      refute row.has_attachments
    end

    test "resolves the program title for a broadcast, and nothing for a direct thread", ctx do
      program = insert(:program_schema, provider_id: ctx.provider.id, title: "Tuesday Judo")

      staff_thread(ctx, type: :program_broadcast, program_id: program.id)
      direct = staff_thread(ctx)

      assert {:ok, rows, false} = ListStaffConversations.execute(ctx.scope)
      by_id = Map.new(rows, &{&1.conversation_id, &1})

      assert by_id[direct.id].program_name == nil
      assert by_id[direct.id].conversation_type == :direct

      broadcast = Enum.find(rows, &(&1.conversation_type == :program_broadcast))
      assert broadcast.program_name == "Tuesday Judo"
    end

    test "pins the fields that exist only so the shared card renders", ctx do
      staff_thread(ctx)

      assert {:ok, [row], false} = ListStaffConversations.execute(ctx.scope)
      assert row.unread_count == 0
      assert row.enrolled_child_names == []
    end
  end

  # Handlers run in the process that emitted the event, and the reads here all happen
  # inline in the test process — so filtering on `self()` keeps this honest under
  # `async: true`, where other tests are querying the same repo concurrently.
  defp count_queries(fun) do
    ref = make_ref()
    test_pid = self()

    :telemetry.attach(
      {__MODULE__, ref},
      [:klass_hero, :repo, :query],
      fn _event, _measurements, _metadata, _config ->
        if self() == test_pid, do: send(test_pid, {ref, :query})
      end,
      nil
    )

    fun.()
    :telemetry.detach({__MODULE__, ref})

    drain(ref, 0)
  end

  defp drain(ref, acc) do
    receive do
      {^ref, :query} -> drain(ref, acc + 1)
    after
      0 -> acc
    end
  end

  describe "execute/2 batching" do
    # The claim the enriched read model is worth its code: cost is flat in page size.
    # An N+1 regression here would be invisible to every other test in this file.
    test "issues the same number of queries however many rows are on the page", ctx do
      for _ <- 1..2, do: staff_thread(ctx)
      two_rows = count_queries(fn -> ListStaffConversations.execute(ctx.scope) end)

      for _ <- 1..8, do: staff_thread(ctx)
      ten_rows = count_queries(fn -> ListStaffConversations.execute(ctx.scope) end)

      assert {:ok, rows, false} = ListStaffConversations.execute(ctx.scope)
      assert length(rows) == 10

      assert two_rows == ten_rows,
             "query count grew with page size: #{two_rows} for 2 rows, #{ten_rows} for 10"
    end

    # The budget, spelled out. Six is: conversations, their participants, display
    # names, the provider's staff ids, the latest message per conversation, and which
    # of those carry attachments. A broadcast adds the program-title lookup; a page of
    # threads with no messages at all spends less, because the attachment and title
    # lookups both short-circuit on an empty list rather than querying for nothing.
    test "spends a fixed query budget, plus one only when a broadcast is on the page", ctx do
      direct = staff_thread(ctx)
      say(direct, ctx.parent, "Is pickup still at four?")

      assert count_queries(fn -> ListStaffConversations.execute(ctx.scope) end) == 6

      program = insert(:program_schema, provider_id: ctx.provider.id, title: "Tuesday Judo")
      broadcast = staff_thread(ctx, type: :program_broadcast, program_id: program.id)
      say(broadcast, ctx.staff_user, "Class is cancelled today")

      assert count_queries(fn -> ListStaffConversations.execute(ctx.scope) end) == 7
    end
  end

  describe "execute/2 pagination" do
    test "reports has_more when more rows exist than the limit", ctx do
      for _ <- 1..3, do: staff_thread(ctx)

      assert {:ok, listed, true} = ListStaffConversations.execute(ctx.scope, limit: 2)
      assert length(listed) == 2
    end

    # Timestamps are pinned a month apart on purpose. `paginate/2`'s cursor is
    # exclusive on `inserted_at` alone, so rows sharing a second cannot be walked
    # apart — the same shape `MonitorConversationsTest` pins.
    test "newest first, and :before walks to the older page", ctx do
      older = staff_thread(ctx, inserted_at: ~N[2026-01-01 10:00:00])
      newer = staff_thread(ctx, inserted_at: ~N[2026-02-01 10:00:00])

      assert {:ok, [first, second], false} = ListStaffConversations.execute(ctx.scope)
      assert first.conversation_id == newer.id
      assert second.conversation_id == older.id

      assert {:ok, [only], false} =
               ListStaffConversations.execute(ctx.scope, before: newer.inserted_at)

      assert only.conversation_id == older.id
    end
  end
end
