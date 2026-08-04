defmodule KlassHero.Messaging.ArchiveConversationsDeliveryTest do
  @moduledoc """
  Integration test for the bulk archive flow end to end: the nightly archive stages
  `conversations_archived` in the same transaction as the write, and the delivery job
  then invokes `ConversationSummaries.project/1`, which is what removes the conversation
  from every participant's inbox.

  The rest of the messaging suite runs against `TestOutbox`, which records staged events
  instead of enqueueing them — so it can assert what a producer emitted, but never what
  its consumers did with the payload. This test swaps in the real `ObanOutbox` for its
  duration to cover that gap, following
  `test/klass_hero/accounts/registration_confirmation_integration_test.exs`.
  """

  use KlassHero.DataCase, async: false

  import KlassHero.Factory

  alias KlassHero.Messaging
  alias KlassHero.Messaging.ArchiveEndedProgramConversations
  alias KlassHero.Shared.Adapters.Driven.Events.ObanOutbox

  describe "archiving conversations for ended programs" do
    test "archives the read-table rows, so the conversation leaves the inbox" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, end_date: DateTime.utc_now() |> DateTime.add(-40, :day))

      conversation =
        insert(:conversation_schema,
          type: "program_broadcast",
          provider_id: provider.id,
          program_id: program.id
        )

      # conversation_summaries has no FKs (see the factory), so a bare id stands in
      # for the participant whose inbox we are asserting on.
      user_id = Ecto.UUID.generate()

      insert(:conversation_summary_schema,
        conversation_id: conversation.id,
        user_id: user_id,
        conversation_type: "program_broadcast",
        provider_id: provider.id,
        program_id: program.id,
        archived_at: nil
      )

      archive_and_deliver()

      {:ok, archived_conversation} = Messaging.get_conversation_by_id(conversation.id)
      summary = Repo.get_by!(Messaging.ConversationSummary, conversation_id: conversation.id, user_id: user_id)

      assert summary.archived_at != nil,
             "the write table archived the conversation but the read table kept archived_at nil"

      assert DateTime.compare(summary.archived_at, archived_conversation.archived_at) == :eq

      assert {:ok, [], false} = Messaging.list_conversation_summaries_for_user(user_id, [])
    end
  end

  # The real outbox is swapped in around the act alone, not in `setup`: under `ObanOutbox`
  # the user fixtures would also deliver their own `user_registered`, which creates a
  # provider profile and collides with the one the factory inserts.
  #
  # Manual mode, then drain: `testing: :inline` would run the delivery job at insert,
  # inside the archive's own transaction. Production runs it after the commit.
  defp archive_and_deliver do
    original_outbox = Application.get_env(:klass_hero, :outbox)
    Application.put_env(:klass_hero, :outbox, module: ObanOutbox)

    result =
      try do
        {:ok, result} =
          Oban.Testing.with_testing_mode(:manual, fn -> ArchiveEndedProgramConversations.execute() end)

        result
      after
        Application.put_env(:klass_hero, :outbox, original_outbox)
      end

    Oban.drain_queue(queue: :critical_events, with_recursion: true)

    result
  end
end
