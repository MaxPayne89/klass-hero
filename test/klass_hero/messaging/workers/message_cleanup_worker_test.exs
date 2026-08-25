defmodule KlassHero.Messaging.Workers.MessageCleanupWorkerTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.EventTestHelper
  alias KlassHero.Messaging.Workers.MessageCleanupWorker

  setup do
    EventTestHelper.setup_test_integration_events()
    :ok
  end

  describe "perform/1" do
    test "returns :ok on success" do
      job = %Oban.Job{args: %{}}

      assert :ok = MessageCleanupWorker.perform(job)
    end

    test "handles args correctly with days_after_program_end override" do
      provider = insert(:provider_profile_schema)

      # Program that ended 10 days ago
      past_end_date = DateTime.utc_now() |> DateTime.add(-10, :day)
      program = insert(:program_schema, end_date: past_end_date)

      conversation =
        insert(:conversation_schema,
          type: "program_broadcast",
          provider_id: provider.id,
          program_id: program.id
        )

      # With 5 day override via args, this should be archived
      job = %Oban.Job{args: %{"days_after_program_end" => 5}}

      assert :ok = MessageCleanupWorker.perform(job)

      # Verify conversation is now archived
      {:ok, archived} = KlassHero.Messaging.get_conversation_by_id(conversation.id)
      assert %DateTime{} = archived.archived_at
    end

    test "returns :ok when no conversations to archive" do
      job = %Oban.Job{args: %{}}

      assert :ok = MessageCleanupWorker.perform(job)

      EventTestHelper.assert_no_integration_events_published()
    end

    test "archives conversations for ended programs and publishes event" do
      provider = insert(:provider_profile_schema)

      # Program that ended 40 days ago
      past_end_date = DateTime.utc_now() |> DateTime.add(-40, :day)
      program = insert(:program_schema, end_date: past_end_date)

      insert(:conversation_schema,
        type: "program_broadcast",
        provider_id: provider.id,
        program_id: program.id
      )

      job = %Oban.Job{args: %{}}

      assert :ok = MessageCleanupWorker.perform(job)

      EventTestHelper.assert_integration_event_published(:conversations_archived, %{reason: :program_ended})
    end

    test "ignores non-integer days_after_program_end values" do
      job = %Oban.Job{args: %{"days_after_program_end" => "invalid"}}

      # Should not crash, just use default
      assert :ok = MessageCleanupWorker.perform(job)
    end

    test "ignores empty args" do
      job = %Oban.Job{args: nil}

      assert :ok = MessageCleanupWorker.perform(job)
    end
  end
end
