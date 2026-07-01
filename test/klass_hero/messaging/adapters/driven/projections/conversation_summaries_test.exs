defmodule KlassHero.Messaging.Adapters.Driven.Projections.ConversationSummariesTest do
  use KlassHero.DataCase, async: false

  import Ecto.Query
  import KlassHero.Factory

  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.ConversationSchema
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.ConversationSummarySchema
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.EnrolledChildrenSchema
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.MessageSchema
  alias KlassHero.Messaging.Adapters.Driven.Projections.ConversationSummaries
  alias KlassHero.Messaging.Participant
  alias KlassHero.Repo
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  # Use a unique name to avoid conflicts with the supervision tree
  @test_server_name :conversation_summaries_projection_test

  setup do
    pid = start_supervised!({ConversationSummaries, name: @test_server_name})
    {:ok, pid: pid}
  end

  describe "bootstrap" do
    test "projects existing conversations into conversation_summaries on startup" do
      # Create two users for a direct conversation
      user_1 = user_fixture(name: "Alice Smith")
      user_2 = user_fixture(name: "Bob Jones")

      # Trigger: conversations table has FK to provider_profiles
      # Why: must create a real provider to satisfy referential integrity
      # Outcome: provider_id is valid for conversation inserts
      provider = insert(:provider_profile_schema)

      # Create a conversation in the write table
      conversation_id = Ecto.UUID.generate()

      Repo.insert!(%ConversationSchema{
        id: conversation_id,
        type: "direct",
        provider_id: provider.id
      })

      # Create participants
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      five_min_ago = DateTime.add(now, -300, :second)

      Repo.insert!(%Participant{
        id: Ecto.UUID.generate(),
        conversation_id: conversation_id,
        user_id: user_1.id,
        joined_at: now,
        last_read_at: five_min_ago
      })

      Repo.insert!(%Participant{
        id: Ecto.UUID.generate(),
        conversation_id: conversation_id,
        user_id: user_2.id,
        joined_at: now,
        last_read_at: nil
      })

      # Create messages — one before and one after user_1's last_read_at
      Repo.insert!(%MessageSchema{
        id: Ecto.UUID.generate(),
        conversation_id: conversation_id,
        sender_id: user_2.id,
        content: "Old message",
        message_type: "text",
        inserted_at: DateTime.add(five_min_ago, -60, :second),
        updated_at: DateTime.add(five_min_ago, -60, :second)
      })

      Repo.insert!(%MessageSchema{
        id: Ecto.UUID.generate(),
        conversation_id: conversation_id,
        sender_id: user_2.id,
        content: "Latest message",
        message_type: "text",
        inserted_at: now,
        updated_at: now
      })

      # Stop the default test server and start a fresh one so it bootstraps
      stop_supervised!(ConversationSummaries)

      bootstrap_name = :"bootstrap_test_#{System.unique_integer([:positive])}"

      bootstrap_pid =
        start_supervised!({ConversationSummaries, name: bootstrap_name}, id: :bootstrap)

      # Synchronize: ensure bootstrap has completed
      _ = :sys.get_state(bootstrap_pid)

      # Verify user_1's summary row
      summary_1 =
        Repo.one(
          from(s in ConversationSummarySchema,
            where: s.conversation_id == ^conversation_id and s.user_id == ^user_1.id
          )
        )

      assert summary_1 != nil
      assert summary_1.conversation_type == "direct"
      assert summary_1.provider_id == provider.id
      assert summary_1.other_participant_name == "Bob Jones"
      assert summary_1.participant_count == 2
      assert summary_1.latest_message_content == "Latest message"
      assert summary_1.latest_message_sender_id == user_2.id
      # user_1 has last_read_at = five_min_ago, and there's 1 message after that
      assert summary_1.unread_count == 1

      # Verify user_2's summary row
      summary_2 =
        Repo.one(
          from(s in ConversationSummarySchema,
            where: s.conversation_id == ^conversation_id and s.user_id == ^user_2.id
          )
        )

      assert summary_2 != nil
      assert summary_2.other_participant_name == "Alice Smith"
      # user_2 has last_read_at = nil, but both messages were sent by user_2
      # themselves — own messages never count as unread
      assert summary_2.unread_count == 0
    end

    test "bootstraps system_notes from existing system messages" do
      user_1 = user_fixture(name: "Alice Smith")
      user_2 = user_fixture(name: "Bob Jones")

      provider = insert(:provider_profile_schema)

      # Create a conversation in the write table
      conversation_id = Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.insert!(%ConversationSchema{
        id: conversation_id,
        type: "direct",
        provider_id: provider.id
      })

      Repo.insert!(%Participant{
        id: Ecto.UUID.generate(),
        conversation_id: conversation_id,
        user_id: user_1.id,
        joined_at: now
      })

      Repo.insert!(%Participant{
        id: Ecto.UUID.generate(),
        conversation_id: conversation_id,
        user_id: user_2.id,
        joined_at: now
      })

      # Insert a system message with a broadcast token
      token = "[broadcast:#{Ecto.UUID.generate()}]"

      Repo.insert!(%MessageSchema{
        id: Ecto.UUID.generate(),
        conversation_id: conversation_id,
        sender_id: user_1.id,
        content: "System note #{token}",
        message_type: "system",
        inserted_at: now,
        updated_at: now
      })

      # Insert a regular text message (should NOT appear in system_notes)
      Repo.insert!(%MessageSchema{
        id: Ecto.UUID.generate(),
        conversation_id: conversation_id,
        sender_id: user_2.id,
        content: "Just a regular message",
        message_type: "text",
        inserted_at: now,
        updated_at: now
      })

      # Stop the default test server and start fresh for bootstrap
      stop_supervised!(ConversationSummaries)

      bootstrap_name = :"bootstrap_sysnotes_#{System.unique_integer([:positive])}"

      bootstrap_pid =
        start_supervised!({ConversationSummaries, name: bootstrap_name},
          id: :bootstrap_sysnotes
        )

      _ = :sys.get_state(bootstrap_pid)

      # Verify the bootstrapped summary row has the token in system_notes
      summary =
        Repo.one(
          from(s in ConversationSummarySchema,
            where: s.conversation_id == ^conversation_id and s.user_id == ^user_1.id
          )
        )

      assert summary != nil

      assert Map.has_key?(summary.system_notes, token),
             "Expected system_notes to contain key #{token}, got: #{inspect(summary.system_notes)}"
    end

    test "populates enrolled_child_names uniformly across parent and provider summary rows" do
      # Trigger: regression test for a bootstrap asymmetry bug —
      #          resolve_enrolled_child_names used to filter by the current row's
      #          user_id, which matched only the parent's row.
      # Why: event-driven path updates all participant rows of a conversation with
      #      the same list; bootstrap must do the same to stay consistent after restart.
      # Outcome: both the parent's and the provider's summary rows carry ["Emma"].
      parent_user = user_fixture(name: "Sarah Johnson")
      provider_user = user_fixture(name: "Claudia Wolf")

      parent = insert(:parent_profile_schema, identity_id: parent_user.id)
      child = insert(:child_schema, first_name: "Emma")
      insert(:child_guardian_schema, child_id: child.id, guardian_id: parent.id)

      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)

      conversation_id = Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.insert!(%ConversationSchema{
        id: conversation_id,
        type: "direct",
        provider_id: provider.id,
        program_id: program.id
      })

      Repo.insert!(%Participant{
        id: Ecto.UUID.generate(),
        conversation_id: conversation_id,
        user_id: parent_user.id,
        joined_at: now
      })

      Repo.insert!(%Participant{
        id: Ecto.UUID.generate(),
        conversation_id: conversation_id,
        user_id: provider_user.id,
        joined_at: now
      })

      Repo.insert!(%EnrolledChildrenSchema{
        id: Ecto.UUID.generate(),
        parent_user_id: parent_user.id,
        program_id: program.id,
        child_id: child.id,
        child_first_name: "Emma",
        inserted_at: now,
        updated_at: now
      })

      stop_supervised!(ConversationSummaries)

      bootstrap_name = :"bootstrap_enrolled_children_#{System.unique_integer([:positive])}"

      bootstrap_pid =
        start_supervised!({ConversationSummaries, name: bootstrap_name},
          id: :bootstrap_enrolled_children
        )

      _ = :sys.get_state(bootstrap_pid)

      parent_summary =
        Repo.one(
          from(s in ConversationSummarySchema,
            where: s.conversation_id == ^conversation_id and s.user_id == ^parent_user.id
          )
        )

      provider_summary =
        Repo.one(
          from(s in ConversationSummarySchema,
            where: s.conversation_id == ^conversation_id and s.user_id == ^provider_user.id
          )
        )

      assert parent_summary.enrolled_child_names == ["Emma"]
      assert provider_summary.enrolled_child_names == ["Emma"]
    end

    test "bootstraps program_name for program_broadcast rows from programs.title" do
      # Trigger: bug #892 — broadcast inbox rows show "Unknown" because
      #          conversation_summaries carries no program-name field.
      # Why: cold-start path must denormalise programs.title onto each
      #      participant's summary row so the UI can render it.
      # Outcome: every participant's broadcast summary carries the program title.
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id, title: "Science Explorers")

      parent_user = user_fixture(name: "Sarah Johnson")
      provider_user = user_fixture(name: "Claudia Wolf")

      conversation_id = Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.insert!(%ConversationSchema{
        id: conversation_id,
        type: "program_broadcast",
        provider_id: provider.id,
        program_id: program.id
      })

      Repo.insert!(%Participant{
        id: Ecto.UUID.generate(),
        conversation_id: conversation_id,
        user_id: parent_user.id,
        joined_at: now
      })

      Repo.insert!(%Participant{
        id: Ecto.UUID.generate(),
        conversation_id: conversation_id,
        user_id: provider_user.id,
        joined_at: now
      })

      stop_supervised!(ConversationSummaries)

      bootstrap_name = :"bootstrap_program_name_#{System.unique_integer([:positive])}"

      bootstrap_pid =
        start_supervised!({ConversationSummaries, name: bootstrap_name}, id: :bootstrap_program_name)

      _ = :sys.get_state(bootstrap_pid)

      summaries =
        Repo.all(from(s in ConversationSummarySchema, where: s.conversation_id == ^conversation_id))

      assert length(summaries) == 2
      assert Enum.all?(summaries, &(&1.conversation_type == "program_broadcast"))
      assert Enum.all?(summaries, &(&1.program_name == "Science Explorers"))
    end
  end

  describe "rebuild/1" do
    test "rebuilds conversation_summaries from write tables without restarting" do
      # Ensure initial bootstrap has completed before inserting test data
      _ = :sys.get_state(@test_server_name)

      user_1 = user_fixture(name: "Alice Rebuild")
      user_2 = user_fixture(name: "Bob Rebuild")
      provider = insert(:provider_profile_schema)

      # Create a conversation in the write table after the projection has started
      conversation_id = Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.insert!(%ConversationSchema{
        id: conversation_id,
        type: "direct",
        provider_id: provider.id
      })

      Repo.insert!(%Participant{
        id: Ecto.UUID.generate(),
        conversation_id: conversation_id,
        user_id: user_1.id,
        joined_at: now
      })

      Repo.insert!(%Participant{
        id: Ecto.UUID.generate(),
        conversation_id: conversation_id,
        user_id: user_2.id,
        joined_at: now
      })

      # The read table should not have this conversation yet
      assert Repo.all(
               from(s in ConversationSummarySchema,
                 where: s.conversation_id == ^conversation_id
               )
             ) == []

      # Rebuild should pick it up from the write tables
      assert :ok = ConversationSummaries.rebuild(@test_server_name)

      summaries =
        Repo.all(
          from(s in ConversationSummarySchema,
            where: s.conversation_id == ^conversation_id
          )
        )

      assert length(summaries) == 2

      summary_1 = Enum.find(summaries, &(&1.user_id == user_1.id))
      assert summary_1.conversation_type == "direct"
      assert summary_1.other_participant_name == "Bob Rebuild"
    end
  end

  describe "handle conversation_created event" do
    test "inserts one summary row per participant for a direct conversation" do
      user_1 = user_fixture(name: "Alice Smith")
      user_2 = user_fixture(name: "Bob Jones")

      conversation_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()

      event =
        IntegrationEvent.new(
          :conversation_created,
          :messaging,
          :conversation,
          conversation_id,
          %{
            conversation_id: conversation_id,
            type: "direct",
            provider_id: provider_id,
            program_id: nil,
            subject: nil,
            participant_ids: [user_1.id, user_2.id]
          }
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:messaging:conversation_created",
        {:integration_event, event}
      )

      # Synchronize: ensure GenServer has processed the broadcast
      _ = :sys.get_state(@test_server_name)

      # Verify user_1's summary row
      summary_1 =
        Repo.one(
          from(s in ConversationSummarySchema,
            where: s.conversation_id == ^conversation_id and s.user_id == ^user_1.id
          )
        )

      assert summary_1 != nil
      assert summary_1.conversation_type == "direct"
      assert summary_1.provider_id == provider_id
      assert summary_1.other_participant_name == "Bob Jones"
      assert summary_1.participant_count == 2
      assert summary_1.unread_count == 0

      # Verify user_2's summary row
      summary_2 =
        Repo.one(
          from(s in ConversationSummarySchema,
            where: s.conversation_id == ^conversation_id and s.user_id == ^user_2.id
          )
        )

      assert summary_2 != nil
      assert summary_2.other_participant_name == "Alice Smith"
      assert summary_2.participant_count == 2
    end

    test "keeps program_name nil when broadcast conversation references unknown program" do
      # Trigger: broadcast event arrives with a program_id that doesn't match any
      #          row in `programs` (rare race or stale event after a delete).
      # Why: the projection must degrade gracefully — UI has its own fallback label.
      # Outcome: summary row inserted with program_name == nil, no crash.
      provider = insert(:provider_profile_schema)
      user = user_fixture(name: "Solo Parent")

      conversation_id = Ecto.UUID.generate()
      missing_program_id = Ecto.UUID.generate()

      event =
        IntegrationEvent.new(
          :conversation_created,
          :messaging,
          :conversation,
          conversation_id,
          %{
            conversation_id: conversation_id,
            type: "program_broadcast",
            provider_id: provider.id,
            program_id: missing_program_id,
            subject: "Welcome",
            participant_ids: [user.id]
          }
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:messaging:conversation_created",
        {:integration_event, event}
      )

      _ = :sys.get_state(@test_server_name)

      summary =
        Repo.one(
          from(s in ConversationSummarySchema,
            where: s.conversation_id == ^conversation_id and s.user_id == ^user.id
          )
        )

      assert summary != nil
      assert summary.conversation_type == "program_broadcast"
      assert summary.program_name == nil
    end

    test "populates program_name on conversation_created for program_broadcast" do
      # Trigger: bug #892 — broadcasts arrive via :conversation_created without a
      #          materialised program label; UI shows "Unknown".
      # Why: the projection must resolve programs.title at event time so brand-new
      #      broadcast threads get a name without waiting for a rebuild.
      # Outcome: each participant's summary row carries the program title.
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id, title: "Forest Friends")

      user_1 = user_fixture(name: "Parent One")
      user_2 = user_fixture(name: "Parent Two")

      conversation_id = Ecto.UUID.generate()

      event =
        IntegrationEvent.new(
          :conversation_created,
          :messaging,
          :conversation,
          conversation_id,
          %{
            conversation_id: conversation_id,
            type: "program_broadcast",
            provider_id: provider.id,
            program_id: program.id,
            subject: "Welcome",
            participant_ids: [user_1.id, user_2.id]
          }
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:messaging:conversation_created",
        {:integration_event, event}
      )

      _ = :sys.get_state(@test_server_name)

      summaries =
        Repo.all(from(s in ConversationSummarySchema, where: s.conversation_id == ^conversation_id))

      assert length(summaries) == 2
      assert Enum.all?(summaries, &(&1.conversation_type == "program_broadcast"))
      assert Enum.all?(summaries, &(&1.program_name == "Forest Friends"))
    end

    test "re-firing event preserves last_read_at and unread_count (idempotent)" do
      user_1 = user_fixture(name: "Alice Smith")
      user_2 = user_fixture(name: "Bob Jones")

      conversation_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()

      event =
        IntegrationEvent.new(
          :conversation_created,
          :messaging,
          :conversation,
          conversation_id,
          %{
            conversation_id: conversation_id,
            type: "direct",
            provider_id: provider_id,
            program_id: nil,
            subject: nil,
            participant_ids: [user_1.id, user_2.id]
          }
        )

      # First firing — creates baseline rows
      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:messaging:conversation_created",
        {:integration_event, event}
      )

      _ = :sys.get_state(@test_server_name)

      # Simulate user_1 having read messages: messages_read flow would set
      # last_read_at and reset unread_count. Mutate directly to isolate the
      # idempotency assertion from the messages_read code path.
      read_at = DateTime.utc_now() |> DateTime.truncate(:second)

      {1, _} =
        Repo.update_all(
          from(s in ConversationSummarySchema,
            where: s.conversation_id == ^conversation_id and s.user_id == ^user_1.id
          ),
          set: [last_read_at: read_at, unread_count: 7]
        )

      # Re-fire the same event — simulates an at-least-once redelivery
      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:messaging:conversation_created",
        {:integration_event, event}
      )

      _ = :sys.get_state(@test_server_name)

      summary_1 =
        Repo.one(
          from(s in ConversationSummarySchema,
            where: s.conversation_id == ^conversation_id and s.user_id == ^user_1.id
          )
        )

      assert summary_1.last_read_at == read_at,
             "last_read_at must survive a :conversation_created replay"

      assert summary_1.unread_count == 7,
             "unread_count must survive a :conversation_created replay"

      # Meta fields should still be in sync with the event payload
      assert summary_1.conversation_type == "direct"
      assert summary_1.provider_id == provider_id
      assert summary_1.other_participant_name == "Bob Jones"
      assert summary_1.participant_count == 2
    end
  end

  describe "handle message_sent event" do
    test "updates latest_message fields and increments unread_count for non-sender" do
      user_1 = user_fixture(name: "Alice Smith")
      user_2 = user_fixture(name: "Bob Jones")

      conversation_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Seed the summary rows first via conversation_created event
      created_event =
        IntegrationEvent.new(
          :conversation_created,
          :messaging,
          :conversation,
          conversation_id,
          %{
            conversation_id: conversation_id,
            type: "direct",
            provider_id: provider_id,
            participant_ids: [user_1.id, user_2.id]
          }
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:messaging:conversation_created",
        {:integration_event, created_event}
      )

      _ = :sys.get_state(@test_server_name)

      # Now send a message_sent event from user_1
      message_id = Ecto.UUID.generate()

      sent_event =
        IntegrationEvent.new(
          :message_sent,
          :messaging,
          :conversation,
          conversation_id,
          %{
            conversation_id: conversation_id,
            message_id: message_id,
            sender_id: user_1.id,
            content: "Hello Bob!",
            message_type: "text",
            sent_at: now
          }
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:messaging:message_sent",
        {:integration_event, sent_event}
      )

      _ = :sys.get_state(@test_server_name)

      # user_2 should have unread_count incremented and latest message updated
      summary_2 =
        Repo.one(
          from(s in ConversationSummarySchema,
            where: s.conversation_id == ^conversation_id and s.user_id == ^user_2.id
          )
        )

      assert summary_2.latest_message_content == "Hello Bob!"
      assert summary_2.latest_message_sender_id == user_1.id
      assert summary_2.latest_message_at == now
      assert summary_2.unread_count == 1

      # user_1 (sender) should have latest message updated but unread_count still 0
      summary_1 =
        Repo.one(
          from(s in ConversationSummarySchema,
            where: s.conversation_id == ^conversation_id and s.user_id == ^user_1.id
          )
        )

      assert summary_1.latest_message_content == "Hello Bob!"
      assert summary_1.latest_message_sender_id == user_1.id
      assert summary_1.unread_count == 0
    end
  end

  describe "handle message_sent event (system notes)" do
    test "projects system note token into system_notes JSONB for system messages" do
      user_1 = user_fixture(name: "Alice Smith")
      user_2 = user_fixture(name: "Bob Jones")

      conversation_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()

      # Create conversation first
      created_event =
        IntegrationEvent.new(
          :conversation_created,
          :messaging,
          :conversation,
          conversation_id,
          %{
            conversation_id: conversation_id,
            type: "direct",
            provider_id: provider_id,
            participant_ids: [user_1.id, user_2.id]
          }
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:messaging:conversation_created",
        {:integration_event, created_event}
      )

      _ = :sys.get_state(@test_server_name)

      # Send a system message with a broadcast token
      token = "[broadcast:#{Ecto.UUID.generate()}]"

      sent_event =
        IntegrationEvent.new(
          :message_sent,
          :messaging,
          :conversation,
          conversation_id,
          %{
            conversation_id: conversation_id,
            message_id: Ecto.UUID.generate(),
            sender_id: user_1.id,
            content: "System note #{token}",
            message_type: "system",
            sent_at: DateTime.utc_now() |> DateTime.truncate(:second)
          }
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:messaging:message_sent",
        {:integration_event, sent_event}
      )

      _ = :sys.get_state(@test_server_name)

      # Both participants should have the token in system_notes
      summaries =
        Repo.all(
          from(s in ConversationSummarySchema,
            where: s.conversation_id == ^conversation_id
          )
        )

      assert length(summaries) == 2

      for summary <- summaries do
        assert Map.has_key?(summary.system_notes, token),
               "Expected system_notes to contain key #{token}, got: #{inspect(summary.system_notes)}"
      end
    end

    test "does not update system_notes for regular text messages" do
      user_1 = user_fixture(name: "Alice Smith")
      user_2 = user_fixture(name: "Bob Jones")

      conversation_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()

      # Create conversation
      created_event =
        IntegrationEvent.new(
          :conversation_created,
          :messaging,
          :conversation,
          conversation_id,
          %{
            conversation_id: conversation_id,
            type: "direct",
            provider_id: provider_id,
            participant_ids: [user_1.id, user_2.id]
          }
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:messaging:conversation_created",
        {:integration_event, created_event}
      )

      _ = :sys.get_state(@test_server_name)

      # Send a regular text message (not system)
      sent_event =
        IntegrationEvent.new(
          :message_sent,
          :messaging,
          :conversation,
          conversation_id,
          %{
            conversation_id: conversation_id,
            message_id: Ecto.UUID.generate(),
            sender_id: user_1.id,
            content: "Just a regular message [broadcast:#{Ecto.UUID.generate()}]",
            message_type: "text",
            sent_at: DateTime.utc_now() |> DateTime.truncate(:second)
          }
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:messaging:message_sent",
        {:integration_event, sent_event}
      )

      _ = :sys.get_state(@test_server_name)

      # system_notes should remain empty
      summaries =
        Repo.all(
          from(s in ConversationSummarySchema,
            where: s.conversation_id == ^conversation_id
          )
        )

      assert length(summaries) == 2

      for summary <- summaries do
        assert summary.system_notes == %{},
               "Expected system_notes to be empty, got: #{inspect(summary.system_notes)}"
      end
    end

    test "system note projection is idempotent" do
      user_1 = user_fixture(name: "Alice Smith")
      user_2 = user_fixture(name: "Bob Jones")

      conversation_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()

      # Create conversation
      created_event =
        IntegrationEvent.new(
          :conversation_created,
          :messaging,
          :conversation,
          conversation_id,
          %{
            conversation_id: conversation_id,
            type: "direct",
            provider_id: provider_id,
            participant_ids: [user_1.id, user_2.id]
          }
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:messaging:conversation_created",
        {:integration_event, created_event}
      )

      _ = :sys.get_state(@test_server_name)

      # Send the same system message event twice
      token = "[broadcast:#{Ecto.UUID.generate()}]"

      sent_event =
        IntegrationEvent.new(
          :message_sent,
          :messaging,
          :conversation,
          conversation_id,
          %{
            conversation_id: conversation_id,
            message_id: Ecto.UUID.generate(),
            sender_id: user_1.id,
            content: "System note #{token}",
            message_type: "system",
            sent_at: DateTime.utc_now() |> DateTime.truncate(:second)
          }
        )

      # Send same event twice
      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:messaging:message_sent",
        {:integration_event, sent_event}
      )

      _ = :sys.get_state(@test_server_name)

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:messaging:message_sent",
        {:integration_event, sent_event}
      )

      _ = :sys.get_state(@test_server_name)

      # system_notes should have exactly 1 key (idempotent merge)
      summary =
        Repo.one(
          from(s in ConversationSummarySchema,
            where: s.conversation_id == ^conversation_id and s.user_id == ^user_1.id
          )
        )

      assert map_size(summary.system_notes) == 1
      assert Map.has_key?(summary.system_notes, token)
    end
  end

  describe "handle messages_read event" do
    test "sets unread_count to 0 and updates last_read_at for the user" do
      user_1 = user_fixture(name: "Alice Smith")
      user_2 = user_fixture(name: "Bob Jones")

      conversation_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Create conversation + send a message so user_2 has unread
      created_event =
        IntegrationEvent.new(
          :conversation_created,
          :messaging,
          :conversation,
          conversation_id,
          %{
            conversation_id: conversation_id,
            type: "direct",
            provider_id: provider_id,
            participant_ids: [user_1.id, user_2.id]
          }
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:messaging:conversation_created",
        {:integration_event, created_event}
      )

      _ = :sys.get_state(@test_server_name)

      sent_event =
        IntegrationEvent.new(
          :message_sent,
          :messaging,
          :conversation,
          conversation_id,
          %{
            conversation_id: conversation_id,
            message_id: Ecto.UUID.generate(),
            sender_id: user_1.id,
            content: "Unread message",
            sent_at: now
          }
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:messaging:message_sent",
        {:integration_event, sent_event}
      )

      _ = :sys.get_state(@test_server_name)

      # Verify user_2 has unread_count = 1
      summary =
        Repo.one(
          from(s in ConversationSummarySchema,
            where: s.conversation_id == ^conversation_id and s.user_id == ^user_2.id
          )
        )

      assert summary.unread_count == 1

      # Now user_2 reads messages
      read_at = DateTime.add(now, 10, :second)

      read_event =
        IntegrationEvent.new(
          :messages_read,
          :messaging,
          :conversation,
          conversation_id,
          %{
            conversation_id: conversation_id,
            user_id: user_2.id,
            read_at: read_at
          }
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:messaging:messages_read",
        {:integration_event, read_event}
      )

      _ = :sys.get_state(@test_server_name)

      # Verify unread_count is now 0
      summary =
        Repo.one(
          from(s in ConversationSummarySchema,
            where: s.conversation_id == ^conversation_id and s.user_id == ^user_2.id
          )
        )

      assert summary.unread_count == 0
      assert summary.last_read_at == read_at
    end
  end

  describe "handle conversation_archived event" do
    test "sets archived_at for all participants of the conversation" do
      user_1 = user_fixture(name: "Alice Smith")
      user_2 = user_fixture(name: "Bob Jones")

      conversation_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Create conversation first
      created_event =
        IntegrationEvent.new(
          :conversation_created,
          :messaging,
          :conversation,
          conversation_id,
          %{
            conversation_id: conversation_id,
            type: "direct",
            provider_id: provider_id,
            participant_ids: [user_1.id, user_2.id]
          }
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:messaging:conversation_created",
        {:integration_event, created_event}
      )

      _ = :sys.get_state(@test_server_name)

      # Now archive it
      archived_event =
        IntegrationEvent.new(
          :conversation_archived,
          :messaging,
          :conversation,
          conversation_id,
          %{
            conversation_id: conversation_id,
            archived_at: now
          }
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:messaging:conversation_archived",
        {:integration_event, archived_event}
      )

      _ = :sys.get_state(@test_server_name)

      # Both participants' summary rows should have archived_at set
      summaries =
        Repo.all(
          from(s in ConversationSummarySchema,
            where: s.conversation_id == ^conversation_id
          )
        )

      assert length(summaries) == 2
      assert Enum.all?(summaries, fn s -> s.archived_at == now end)
    end
  end

  describe "handle conversations_archived event" do
    test "sets archived_at for all participants across multiple conversations" do
      user_1 = user_fixture(name: "Alice Smith")
      user_2 = user_fixture(name: "Bob Jones")
      provider_id = Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      conv_1_id = Ecto.UUID.generate()
      conv_2_id = Ecto.UUID.generate()

      # Create two conversations
      for conv_id <- [conv_1_id, conv_2_id] do
        event =
          IntegrationEvent.new(
            :conversation_created,
            :messaging,
            :conversation,
            conv_id,
            %{
              conversation_id: conv_id,
              type: "direct",
              provider_id: provider_id,
              participant_ids: [user_1.id, user_2.id]
            }
          )

        Phoenix.PubSub.broadcast(
          KlassHero.PubSub,
          "integration:messaging:conversation_created",
          {:integration_event, event}
        )

        _ = :sys.get_state(@test_server_name)
      end

      # Bulk archive both conversations
      bulk_event =
        IntegrationEvent.new(
          :conversations_archived,
          :messaging,
          :conversation,
          "bulk_archive_#{System.unique_integer([:positive])}",
          %{
            conversation_ids: [conv_1_id, conv_2_id],
            archived_at: now
          }
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:messaging:conversations_archived",
        {:integration_event, bulk_event}
      )

      _ = :sys.get_state(@test_server_name)

      # All 4 summary rows (2 per conversation) should have archived_at set
      summaries =
        Repo.all(
          from(s in ConversationSummarySchema,
            where: s.conversation_id in ^[conv_1_id, conv_2_id]
          )
        )

      assert length(summaries) == 4
      assert Enum.all?(summaries, fn s -> s.archived_at == now end)
    end
  end

  describe "handle message_data_anonymized event" do
    test "updates other_participant_name to 'Deleted User' for the anonymized user" do
      user_1 = user_fixture(name: "Alice Smith")
      user_2 = user_fixture(name: "Bob Jones")

      conversation_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()

      # Create conversation
      created_event =
        IntegrationEvent.new(
          :conversation_created,
          :messaging,
          :conversation,
          conversation_id,
          %{
            conversation_id: conversation_id,
            type: "direct",
            provider_id: provider_id,
            participant_ids: [user_1.id, user_2.id]
          }
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:messaging:conversation_created",
        {:integration_event, created_event}
      )

      _ = :sys.get_state(@test_server_name)

      # Verify initial names are correct
      summary_1 =
        Repo.one(
          from(s in ConversationSummarySchema,
            where: s.conversation_id == ^conversation_id and s.user_id == ^user_1.id
          )
        )

      assert summary_1.other_participant_name == "Bob Jones"

      # Anonymize user_2
      anonymize_event =
        IntegrationEvent.new(
          :message_data_anonymized,
          :messaging,
          :user,
          user_2.id,
          %{user_id: user_2.id}
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:messaging:message_data_anonymized",
        {:integration_event, anonymize_event}
      )

      _ = :sys.get_state(@test_server_name)

      # user_1's summary should now show "Deleted User" as the other participant
      summary_1 =
        Repo.one(
          from(s in ConversationSummarySchema,
            where: s.conversation_id == ^conversation_id and s.user_id == ^user_1.id
          )
        )

      assert summary_1.other_participant_name == "Deleted User"

      # user_2's summary should remain unchanged (their own name display is not affected)
      summary_2 =
        Repo.one(
          from(s in ConversationSummarySchema,
            where: s.conversation_id == ^conversation_id and s.user_id == ^user_2.id
          )
        )

      assert summary_2.other_participant_name == "Alice Smith"
    end
  end

  describe "staff participant summaries" do
    test "rebuild creates summary rows for staff participants in 3-participant direct conversations" do
      # Ensure initial bootstrap has completed before inserting test data
      _ = :sys.get_state(@test_server_name)

      provider = insert(:provider_profile_schema)
      parent_user = user_fixture(name: "Parent User")
      staff_user = user_fixture(name: "Staff Member")

      conversation_id = Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.insert!(%ConversationSchema{
        id: conversation_id,
        type: "direct",
        provider_id: provider.id
      })

      # Insert participants: owner first, then parent, then staff
      Repo.insert!(%Participant{
        id: Ecto.UUID.generate(),
        conversation_id: conversation_id,
        user_id: provider.identity_id,
        joined_at: now
      })

      Repo.insert!(%Participant{
        id: Ecto.UUID.generate(),
        conversation_id: conversation_id,
        user_id: parent_user.id,
        joined_at: now
      })

      Repo.insert!(%Participant{
        id: Ecto.UUID.generate(),
        conversation_id: conversation_id,
        user_id: staff_user.id,
        joined_at: now
      })

      # Rebuild projection
      assert :ok = ConversationSummaries.rebuild(@test_server_name)

      # All 3 participants should have a summary row
      all_summaries =
        Repo.all(
          from(s in ConversationSummarySchema,
            where: s.conversation_id == ^conversation_id
          )
        )

      assert length(all_summaries) == 3

      # Staff should have a summary row (also verifiable via the list helper)
      staff_summaries = list_summaries_for_user(staff_user.id)
      assert length(staff_summaries) == 1
      staff_summary = hd(staff_summaries)
      assert staff_summary.conversation_id == conversation_id
      assert staff_summary.conversation_type == "direct"
      assert staff_summary.participant_count == 3

      # Owner should have a summary row
      owner_summary = Enum.find(all_summaries, &(&1.user_id == provider.identity_id))
      assert owner_summary != nil, "Expected a summary row for the owner participant"

      # Parent should have a summary row
      parent_summary = Enum.find(all_summaries, &(&1.user_id == parent_user.id))
      assert parent_summary != nil, "Expected a summary row for the parent participant"
    end

    test "staff participant sees parent name as other_participant_name" do
      _ = :sys.get_state(@test_server_name)

      provider = insert(:provider_profile_schema)
      parent_user = user_fixture(name: "Parent User")
      staff_user = user_fixture(name: "Staff Member")

      conversation_id = Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.insert!(%ConversationSchema{
        id: conversation_id,
        type: "direct",
        provider_id: provider.id
      })

      # Use distinct joined_at timestamps to guarantee ordering via preload_order
      Repo.insert!(%Participant{
        id: Ecto.UUID.generate(),
        conversation_id: conversation_id,
        user_id: parent_user.id,
        joined_at: now
      })

      Repo.insert!(%Participant{
        id: Ecto.UUID.generate(),
        conversation_id: conversation_id,
        user_id: provider.identity_id,
        joined_at: DateTime.add(now, 1, :second)
      })

      Repo.insert!(%Participant{
        id: Ecto.UUID.generate(),
        conversation_id: conversation_id,
        user_id: staff_user.id,
        joined_at: DateTime.add(now, 2, :second)
      })

      assert :ok = ConversationSummaries.rebuild(@test_server_name)

      staff_summary =
        Repo.one(
          from(s in ConversationSummarySchema,
            where: s.conversation_id == ^conversation_id and s.user_id == ^staff_user.id
          )
        )

      assert staff_summary != nil
      # Staff sees the first non-staff participant, which is parent
      assert staff_summary.other_participant_name == "Parent User"
    end
  end

  describe "handle participant_added event" do
    test "upserts a summary row for each newly added participant on a direct conversation" do
      _ = :sys.get_state(@test_server_name)

      provider = insert(:provider_profile_schema)
      parent = user_fixture(name: "Parent One")
      provider_user = user_fixture(name: "Provider Owner")
      staff = user_fixture(name: "Staff Late")

      conversation_id = Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.insert!(%ConversationSchema{
        id: conversation_id,
        type: "direct",
        provider_id: provider.id
      })

      for {uid, ts} <- [{parent.id, now}, {provider_user.id, DateTime.add(now, 1, :second)}] do
        Repo.insert!(%Participant{
          id: Ecto.UUID.generate(),
          conversation_id: conversation_id,
          user_id: uid,
          joined_at: ts
        })
      end

      # Seed an existing message so the new participant's summary back-fills
      # last-message data and unread_count
      Repo.insert!(%MessageSchema{
        id: Ecto.UUID.generate(),
        conversation_id: conversation_id,
        sender_id: parent.id,
        content: "Hi there",
        message_type: "text",
        inserted_at: now,
        updated_at: now
      })

      # Add staff participant in write model — projection event follows
      Repo.insert!(%Participant{
        id: Ecto.UUID.generate(),
        conversation_id: conversation_id,
        user_id: staff.id,
        joined_at: DateTime.add(now, 2, :second)
      })

      event =
        IntegrationEvent.new(
          :participant_added,
          :messaging,
          :conversation,
          conversation_id,
          %{
            conversation_id: conversation_id,
            participant_user_ids: [staff.id],
            source: :later_assignment
          }
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:messaging:participant_added",
        {:integration_event, event}
      )

      _ = :sys.get_state(@test_server_name)

      summary =
        Repo.one(
          from(s in ConversationSummarySchema,
            where: s.conversation_id == ^conversation_id and s.user_id == ^staff.id
          )
        )

      assert summary != nil, "staff summary row must exist after :participant_added"
      assert summary.conversation_type == "direct"
      assert summary.provider_id == provider.id
      assert summary.participant_count == 3
      assert summary.latest_message_content == "Hi there"
      assert summary.latest_message_sender_id == parent.id
      assert summary.unread_count == 1
      assert summary.archived_at == nil
    end

    test "re-firing event preserves last_read_at and unread_count (idempotent replay)" do
      _ = :sys.get_state(@test_server_name)

      provider = insert(:provider_profile_schema)
      parent = user_fixture(name: "Parent One")
      staff = user_fixture(name: "Staff Late")

      conversation_id = Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.insert!(%ConversationSchema{
        id: conversation_id,
        type: "direct",
        provider_id: provider.id
      })

      Repo.insert!(%Participant{
        id: Ecto.UUID.generate(),
        conversation_id: conversation_id,
        user_id: parent.id,
        joined_at: now
      })

      Repo.insert!(%Participant{
        id: Ecto.UUID.generate(),
        conversation_id: conversation_id,
        user_id: staff.id,
        joined_at: DateTime.add(now, 1, :second)
      })

      event =
        IntegrationEvent.new(
          :participant_added,
          :messaging,
          :conversation,
          conversation_id,
          %{
            conversation_id: conversation_id,
            participant_user_ids: [staff.id],
            source: :later_assignment
          }
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:messaging:participant_added",
        {:integration_event, event}
      )

      _ = :sys.get_state(@test_server_name)

      # Staff reads the conversation: simulate by setting last_read_at + zeroing unread
      read_at = DateTime.utc_now() |> DateTime.truncate(:second)

      {1, _} =
        Repo.update_all(
          from(s in ConversationSummarySchema,
            where: s.conversation_id == ^conversation_id and s.user_id == ^staff.id
          ),
          set: [last_read_at: read_at, unread_count: 0]
        )

      # Replay the same event
      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:messaging:participant_added",
        {:integration_event, event}
      )

      _ = :sys.get_state(@test_server_name)

      summary =
        Repo.one(
          from(s in ConversationSummarySchema,
            where: s.conversation_id == ^conversation_id and s.user_id == ^staff.id
          )
        )

      assert summary.last_read_at == read_at,
             "last_read_at must survive a :participant_added replay"

      assert summary.unread_count == 0,
             "unread_count must survive a :participant_added replay"
    end

    test "inserts one summary row per user_id when payload carries a batch" do
      _ = :sys.get_state(@test_server_name)

      provider = insert(:provider_profile_schema)
      parent = user_fixture(name: "Parent One")
      staff_a = user_fixture(name: "Staff A")
      staff_b = user_fixture(name: "Staff B")

      conversation_id = Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.insert!(%ConversationSchema{
        id: conversation_id,
        type: "direct",
        provider_id: provider.id
      })

      for {uid, ts} <- [
            {parent.id, now},
            {staff_a.id, DateTime.add(now, 1, :second)},
            {staff_b.id, DateTime.add(now, 2, :second)}
          ] do
        Repo.insert!(%Participant{
          id: Ecto.UUID.generate(),
          conversation_id: conversation_id,
          user_id: uid,
          joined_at: ts
        })
      end

      event =
        IntegrationEvent.new(
          :participant_added,
          :messaging,
          :conversation,
          conversation_id,
          %{
            conversation_id: conversation_id,
            participant_user_ids: [staff_a.id, staff_b.id],
            source: :initial_staff
          }
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:messaging:participant_added",
        {:integration_event, event}
      )

      _ = :sys.get_state(@test_server_name)

      summaries =
        Repo.all(
          from(s in ConversationSummarySchema,
            where:
              s.conversation_id == ^conversation_id and
                s.user_id in ^[staff_a.id, staff_b.id],
            order_by: s.user_id
          )
        )

      assert length(summaries) == 2
      assert Enum.all?(summaries, &(&1.participant_count == 3))
      assert Enum.all?(summaries, &(&1.conversation_type == "direct"))
    end

    test "inserts row for broadcast conversation with nil other_participant_name" do
      _ = :sys.get_state(@test_server_name)

      provider = insert(:provider_profile_schema)
      staff = user_fixture(name: "Staff Late")

      conversation_id = Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.insert!(%ConversationSchema{
        id: conversation_id,
        type: "program_broadcast",
        provider_id: provider.id
      })

      Repo.insert!(%Participant{
        id: Ecto.UUID.generate(),
        conversation_id: conversation_id,
        user_id: staff.id,
        joined_at: now
      })

      event =
        IntegrationEvent.new(
          :participant_added,
          :messaging,
          :conversation,
          conversation_id,
          %{
            conversation_id: conversation_id,
            participant_user_ids: [staff.id],
            source: :later_assignment
          }
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:messaging:participant_added",
        {:integration_event, event}
      )

      _ = :sys.get_state(@test_server_name)

      summary =
        Repo.one(
          from(s in ConversationSummarySchema,
            where: s.conversation_id == ^conversation_id and s.user_id == ^staff.id
          )
        )

      assert summary != nil
      assert summary.conversation_type == "program_broadcast"
      assert summary.other_participant_name == nil
    end
  end

  describe "handle participant_removed event" do
    test "soft-archives the summary row for the removed user" do
      _ = :sys.get_state(@test_server_name)

      user_1 = user_fixture(name: "Alice Smith")
      staff = user_fixture(name: "Staff Out")

      conversation_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()

      created =
        IntegrationEvent.new(
          :conversation_created,
          :messaging,
          :conversation,
          conversation_id,
          %{
            conversation_id: conversation_id,
            type: "direct",
            provider_id: provider_id,
            participant_ids: [user_1.id, staff.id]
          }
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:messaging:conversation_created",
        {:integration_event, created}
      )

      _ = :sys.get_state(@test_server_name)

      removed =
        IntegrationEvent.new(
          :participant_removed,
          :messaging,
          :conversation,
          conversation_id,
          %{
            conversation_id: conversation_id,
            participant_user_ids: [staff.id],
            source: :staff_unassignment
          }
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:messaging:participant_removed",
        {:integration_event, removed}
      )

      _ = :sys.get_state(@test_server_name)

      staff_summary =
        Repo.one(
          from(s in ConversationSummarySchema,
            where: s.conversation_id == ^conversation_id and s.user_id == ^staff.id
          )
        )

      assert staff_summary != nil
      assert staff_summary.archived_at != nil

      # Non-removed users keep their row intact
      user_1_summary =
        Repo.one(
          from(s in ConversationSummarySchema,
            where: s.conversation_id == ^conversation_id and s.user_id == ^user_1.id
          )
        )

      assert user_1_summary.archived_at == nil
    end

    test "replay preserves the first archived_at timestamp (COALESCE idempotency)" do
      _ = :sys.get_state(@test_server_name)

      user_1 = user_fixture(name: "Alice Smith")
      staff = user_fixture(name: "Staff Out")

      conversation_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()

      created =
        IntegrationEvent.new(
          :conversation_created,
          :messaging,
          :conversation,
          conversation_id,
          %{
            conversation_id: conversation_id,
            type: "direct",
            provider_id: provider_id,
            participant_ids: [user_1.id, staff.id]
          }
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:messaging:conversation_created",
        {:integration_event, created}
      )

      _ = :sys.get_state(@test_server_name)

      removed =
        IntegrationEvent.new(
          :participant_removed,
          :messaging,
          :conversation,
          conversation_id,
          %{
            conversation_id: conversation_id,
            participant_user_ids: [staff.id],
            source: :staff_unassignment
          }
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:messaging:participant_removed",
        {:integration_event, removed}
      )

      _ = :sys.get_state(@test_server_name)

      first =
        Repo.one(
          from(s in ConversationSummarySchema,
            where: s.conversation_id == ^conversation_id and s.user_id == ^staff.id,
            select: s.archived_at
          )
        )

      # Replay later — the second archived_at would differ if the handler
      # blindly overwrote. COALESCE keeps the original.
      Process.sleep(1_100)

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:messaging:participant_removed",
        {:integration_event, removed}
      )

      _ = :sys.get_state(@test_server_name)

      second =
        Repo.one(
          from(s in ConversationSummarySchema,
            where: s.conversation_id == ^conversation_id and s.user_id == ^staff.id,
            select: s.archived_at
          )
        )

      assert second == first, "first removal's archived_at must win on replay"
    end

    test "archives multiple users in a single batch event" do
      _ = :sys.get_state(@test_server_name)

      user_1 = user_fixture(name: "Alice Smith")
      staff_a = user_fixture(name: "Staff A")
      staff_b = user_fixture(name: "Staff B")

      conversation_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()

      created =
        IntegrationEvent.new(
          :conversation_created,
          :messaging,
          :conversation,
          conversation_id,
          %{
            conversation_id: conversation_id,
            type: "direct",
            provider_id: provider_id,
            participant_ids: [user_1.id, staff_a.id, staff_b.id]
          }
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:messaging:conversation_created",
        {:integration_event, created}
      )

      _ = :sys.get_state(@test_server_name)

      removed =
        IntegrationEvent.new(
          :participant_removed,
          :messaging,
          :conversation,
          conversation_id,
          %{
            conversation_id: conversation_id,
            participant_user_ids: [staff_a.id, staff_b.id],
            source: :staff_unassignment
          }
        )

      Phoenix.PubSub.broadcast(
        KlassHero.PubSub,
        "integration:messaging:participant_removed",
        {:integration_event, removed}
      )

      _ = :sys.get_state(@test_server_name)

      archived_count =
        Repo.aggregate(
          from(s in ConversationSummarySchema,
            where:
              s.conversation_id == ^conversation_id and
                s.user_id in ^[staff_a.id, staff_b.id] and
                not is_nil(s.archived_at)
          ),
          :count,
          :id
        )

      assert archived_count == 2
    end
  end

  # Helper to create users with specific names
  defp user_fixture(attrs) do
    KlassHero.AccountsFixtures.user_fixture(attrs)
  end

  defp list_summaries_for_user(user_id) do
    Repo.all(
      from(s in ConversationSummarySchema,
        where: s.user_id == ^user_id
      )
    )
  end

  describe "macro invariants after happy-path startup" do
    test "state.retry_count == 0 after first event projects successfully" do
      pid =
        start_supervised!(
          {ConversationSummaries, name: :"reg_#{System.unique_integer([:positive])}"},
          id: :regression_projection
        )

      :sys.get_state(pid)

      assert %{bootstrapped: true, retry_count: 0} = :sys.get_state(pid)

      user_1 = user_fixture(name: "Alice Macro")
      user_2 = user_fixture(name: "Bob Macro")

      conversation_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()

      event =
        IntegrationEvent.new(
          :conversation_created,
          :messaging,
          :conversation,
          conversation_id,
          %{
            conversation_id: conversation_id,
            participant_ids: [user_1.id, user_2.id],
            type: "direct",
            provider_id: provider_id,
            program_id: nil,
            subject: nil
          }
        )

      send(pid, {:integration_event, event})
      :sys.get_state(pid)

      assert %{bootstrapped: true, retry_count: 0} = :sys.get_state(pid)
    end
  end
end
