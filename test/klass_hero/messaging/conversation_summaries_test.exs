defmodule KlassHero.Messaging.ConversationSummariesTest do
  use KlassHero.DataCase, async: false

  import Ecto.Query
  import KlassHero.EventTestHelper, only: [through_outbox: 1]
  import KlassHero.Factory

  alias KlassHero.Messaging
  alias KlassHero.Messaging.Conversation
  alias KlassHero.Messaging.ConversationSummaries
  alias KlassHero.Messaging.ConversationSummary
  alias KlassHero.Messaging.EnrolledChild
  alias KlassHero.Messaging.Events
  alias KlassHero.Messaging.Message
  alias KlassHero.Messaging.Participant
  alias KlassHero.Repo
  alias KlassHero.Shared.Domain.Events.Event

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

      conversation_id = Ecto.UUID.generate()
      five_min_ago = DateTime.add(now(), -300, :second)

      insert_conversation(id: conversation_id, type: :direct, provider_id: provider.id)

      insert_participant(conversation_id, user_id: user_1.id, joined_at: now(), last_read_at: five_min_ago)
      insert_participant(conversation_id, user_id: user_2.id, joined_at: now(), last_read_at: nil)

      # Messages — one before and one after user_1's last_read_at
      insert_message(conversation_id,
        sender_id: user_2.id,
        content: "Old message",
        inserted_at: DateTime.add(five_min_ago, -60, :second)
      )

      insert_message(conversation_id, sender_id: user_2.id, content: "Latest message")

      _ = restart_for_bootstrap(:bootstrap)

      # Verify user_1's summary row
      summary_1 =
        Repo.one(
          from(s in ConversationSummary,
            where: s.conversation_id == ^conversation_id and s.user_id == ^user_1.id
          )
        )

      assert summary_1 != nil
      assert summary_1.conversation_type == :direct
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
          from(s in ConversationSummary,
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
      conversation_id = Ecto.UUID.generate()

      insert_conversation(id: conversation_id, type: :direct, provider_id: provider.id)
      insert_participant(conversation_id, user_id: user_1.id, joined_at: now())
      insert_participant(conversation_id, user_id: user_2.id, joined_at: now())

      # Insert a system message with a broadcast token
      token = "[broadcast:#{Ecto.UUID.generate()}]"

      insert_message(conversation_id,
        sender_id: user_1.id,
        content: "System note #{token}",
        message_type: :system
      )

      # Insert a regular text message (should NOT appear in system_notes)
      insert_message(conversation_id, sender_id: user_2.id, content: "Just a regular message")

      _ = restart_for_bootstrap(:bootstrap_sysnotes)

      # Verify the bootstrapped summary row has the token in system_notes
      summary =
        Repo.one(
          from(s in ConversationSummary,
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

      insert_conversation(id: conversation_id, type: :direct, provider_id: provider.id, program_id: program.id)
      insert_participant(conversation_id, user_id: parent_user.id, joined_at: now())
      insert_participant(conversation_id, user_id: provider_user.id, joined_at: now())

      Repo.insert!(%EnrolledChild{
        id: Ecto.UUID.generate(),
        parent_user_id: parent_user.id,
        program_id: program.id,
        child_id: child.id,
        child_first_name: "Emma",
        inserted_at: now(),
        updated_at: now()
      })

      _ = restart_for_bootstrap(:bootstrap_enrolled_children)

      parent_summary =
        Repo.one(
          from(s in ConversationSummary,
            where: s.conversation_id == ^conversation_id and s.user_id == ^parent_user.id
          )
        )

      provider_summary =
        Repo.one(
          from(s in ConversationSummary,
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

      insert_conversation(
        id: conversation_id,
        type: :program_broadcast,
        provider_id: provider.id,
        program_id: program.id
      )

      insert_participant(conversation_id, user_id: parent_user.id, joined_at: now())
      insert_participant(conversation_id, user_id: provider_user.id, joined_at: now())

      _ = restart_for_bootstrap(:bootstrap_program_name)

      summaries =
        Repo.all(from(s in ConversationSummary, where: s.conversation_id == ^conversation_id))

      assert length(summaries) == 2
      assert Enum.all?(summaries, &(&1.conversation_type == :program_broadcast))
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

      insert_conversation(id: conversation_id, type: :direct, provider_id: provider.id)
      insert_participant(conversation_id, user_id: user_1.id, joined_at: now())
      insert_participant(conversation_id, user_id: user_2.id, joined_at: now())

      # The read table should not have this conversation yet
      assert Repo.all(
               from(s in ConversationSummary,
                 where: s.conversation_id == ^conversation_id
               )
             ) == []

      # Rebuild should pick it up from the write tables
      assert :ok = ConversationSummaries.rebuild(@test_server_name)

      summaries =
        Repo.all(
          from(s in ConversationSummary,
            where: s.conversation_id == ^conversation_id
          )
        )

      assert length(summaries) == 2

      summary_1 = Enum.find(summaries, &(&1.user_id == user_1.id))
      assert summary_1.conversation_type == :direct
      assert summary_1.other_participant_name == "Bob Rebuild"
    end
  end

  describe "handle conversation_created event" do
    test "inserts one summary row per participant for a direct conversation" do
      user_1 = user_fixture(name: "Alice Smith")
      user_2 = user_fixture(name: "Bob Jones")

      conversation_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()

      dispatch(:conversation_created, %{
        conversation_id: conversation_id,
        type: :direct,
        provider_id: provider_id,
        program_id: nil,
        subject: nil,
        participant_ids: [user_1.id, user_2.id]
      })

      # Verify user_1's summary row
      summary_1 =
        Repo.one(
          from(s in ConversationSummary,
            where: s.conversation_id == ^conversation_id and s.user_id == ^user_1.id
          )
        )

      assert summary_1 != nil
      assert summary_1.conversation_type == :direct
      assert summary_1.provider_id == provider_id
      assert summary_1.other_participant_name == "Bob Jones"
      assert summary_1.participant_count == 2
      assert summary_1.unread_count == 0

      # Verify user_2's summary row
      summary_2 =
        Repo.one(
          from(s in ConversationSummary,
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

      dispatch(:conversation_created, %{
        conversation_id: conversation_id,
        type: :program_broadcast,
        provider_id: provider.id,
        program_id: missing_program_id,
        subject: "Welcome",
        participant_ids: [user.id]
      })

      summary =
        Repo.one(
          from(s in ConversationSummary,
            where: s.conversation_id == ^conversation_id and s.user_id == ^user.id
          )
        )

      assert summary != nil
      assert summary.conversation_type == :program_broadcast
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

      dispatch(:conversation_created, %{
        conversation_id: conversation_id,
        type: :program_broadcast,
        provider_id: provider.id,
        program_id: program.id,
        subject: "Welcome",
        participant_ids: [user_1.id, user_2.id]
      })

      summaries =
        Repo.all(from(s in ConversationSummary, where: s.conversation_id == ^conversation_id))

      assert length(summaries) == 2
      assert Enum.all?(summaries, &(&1.conversation_type == :program_broadcast))
      assert Enum.all?(summaries, &(&1.program_name == "Forest Friends"))
    end

    test "re-firing event preserves last_read_at and unread_count (idempotent)" do
      user_1 = user_fixture(name: "Alice Smith")
      user_2 = user_fixture(name: "Bob Jones")

      conversation_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()

      created =
        event(:conversation_created, %{
          conversation_id: conversation_id,
          type: :direct,
          provider_id: provider_id,
          program_id: nil,
          subject: nil,
          participant_ids: [user_1.id, user_2.id]
        })

      # First firing — creates baseline rows
      dispatch(created)

      # Simulate user_1 having read messages: messages_read flow would set
      # last_read_at and reset unread_count. Mutate directly to isolate the
      # idempotency assertion from the messages_read code path.
      read_at = now()

      {1, _} =
        Repo.update_all(
          from(s in ConversationSummary,
            where: s.conversation_id == ^conversation_id and s.user_id == ^user_1.id
          ),
          set: [last_read_at: read_at, unread_count: 7]
        )

      # Re-fire the same event — simulates an at-least-once redelivery
      dispatch(created)

      summary_1 =
        Repo.one(
          from(s in ConversationSummary,
            where: s.conversation_id == ^conversation_id and s.user_id == ^user_1.id
          )
        )

      assert summary_1.last_read_at == read_at,
             "last_read_at must survive a :conversation_created replay"

      assert summary_1.unread_count == 7,
             "unread_count must survive a :conversation_created replay"

      # Meta fields should still be in sync with the event payload
      assert summary_1.conversation_type == :direct
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
      sent_at = now()

      # Seed the summary rows first via conversation_created event
      dispatch(:conversation_created, %{
        conversation_id: conversation_id,
        type: :direct,
        provider_id: provider_id,
        participant_ids: [user_1.id, user_2.id]
      })

      # Now send a message_sent event from user_1
      dispatch(:message_sent, %{
        conversation_id: conversation_id,
        message_id: Ecto.UUID.generate(),
        sender_id: user_1.id,
        content: "Hello Bob!",
        message_type: :text,
        sent_at: sent_at
      })

      # user_2 should have unread_count incremented and latest message updated
      summary_2 =
        Repo.one(
          from(s in ConversationSummary,
            where: s.conversation_id == ^conversation_id and s.user_id == ^user_2.id
          )
        )

      assert summary_2.latest_message_content == "Hello Bob!"
      assert summary_2.latest_message_sender_id == user_1.id
      assert summary_2.latest_message_at == sent_at
      assert summary_2.unread_count == 1

      # user_1 (sender) should have latest message updated but unread_count still 0
      summary_1 =
        Repo.one(
          from(s in ConversationSummary,
            where: s.conversation_id == ^conversation_id and s.user_id == ^user_1.id
          )
        )

      assert summary_1.latest_message_content == "Hello Bob!"
      assert summary_1.latest_message_sender_id == user_1.id
      assert summary_1.unread_count == 0
    end
  end

  # The conversation list reads this table, so it must not be told to refetch
  # before the rows are current. Notifying from the producer instead — where every
  # other notification in this codebase is sent from — would race the job that
  # runs this projection, and the list would re-render the rows it already had.
  describe "notifying the conversation list" do
    test "tells each participant only after their row is written" do
      user_1 = user_fixture(name: "Alice Smith")
      user_2 = user_fixture(name: "Bob Jones")
      conversation_id = Ecto.UUID.generate()

      for user <- [user_1, user_2] do
        Phoenix.PubSub.subscribe(KlassHero.PubSub, Messaging.user_messages_topic(user.id))
      end

      dispatch(:conversation_created, %{
        conversation_id: conversation_id,
        type: :direct,
        provider_id: Ecto.UUID.generate(),
        participant_ids: [user_1.id, user_2.id]
      })

      # Two participants, one message each — and the rows are already readable.
      assert_receive :conversations_changed
      assert_receive :conversations_changed
      refute_receive :conversations_changed, 50

      assert Repo.aggregate(
               from(s in ConversationSummary, where: s.conversation_id == ^conversation_id),
               :count
             ) == 2
    end

    test "a new message tells exactly the users whose summary row it touched" do
      user_1 = user_fixture(name: "Alice Smith")
      user_2 = user_fixture(name: "Bob Jones")
      outsider = user_fixture(name: "Carol Nobody")
      conversation_id = Ecto.UUID.generate()

      dispatch(:conversation_created, %{
        conversation_id: conversation_id,
        type: :direct,
        provider_id: Ecto.UUID.generate(),
        participant_ids: [user_1.id, user_2.id]
      })

      for user <- [user_1, user_2, outsider] do
        Phoenix.PubSub.subscribe(KlassHero.PubSub, Messaging.user_messages_topic(user.id))
      end

      dispatch(:message_sent, %{
        conversation_id: conversation_id,
        message_id: Ecto.UUID.generate(),
        sender_id: user_1.id,
        content: "Hello Bob!",
        message_type: :text,
        sent_at: now()
      })

      # Both participants — the sender's own list moves too, its latest-message
      # preview changed. The outsider has no row, so no message.
      assert_receive :conversations_changed
      assert_receive :conversations_changed
      refute_receive :conversations_changed, 50
    end
  end

  describe "handle message_sent event (system notes)" do
    test "projects system note token into system_notes JSONB for system messages" do
      user_1 = user_fixture(name: "Alice Smith")
      user_2 = user_fixture(name: "Bob Jones")

      conversation_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()

      # Create conversation first
      dispatch(:conversation_created, %{
        conversation_id: conversation_id,
        type: :direct,
        provider_id: provider_id,
        participant_ids: [user_1.id, user_2.id]
      })

      # Send a system message with a broadcast token
      token = "[broadcast:#{Ecto.UUID.generate()}]"

      dispatch(:message_sent, %{
        conversation_id: conversation_id,
        message_id: Ecto.UUID.generate(),
        sender_id: user_1.id,
        content: "System note #{token}",
        message_type: :system,
        sent_at: now()
      })

      # Both participants should have the token in system_notes
      summaries =
        Repo.all(
          from(s in ConversationSummary,
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
      dispatch(:conversation_created, %{
        conversation_id: conversation_id,
        type: :direct,
        provider_id: provider_id,
        participant_ids: [user_1.id, user_2.id]
      })

      # Send a regular text message (not system)
      dispatch(:message_sent, %{
        conversation_id: conversation_id,
        message_id: Ecto.UUID.generate(),
        sender_id: user_1.id,
        content: "Just a regular message [broadcast:#{Ecto.UUID.generate()}]",
        message_type: :text,
        sent_at: now()
      })

      # system_notes should remain empty
      summaries =
        Repo.all(
          from(s in ConversationSummary,
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
      dispatch(:conversation_created, %{
        conversation_id: conversation_id,
        type: :direct,
        provider_id: provider_id,
        participant_ids: [user_1.id, user_2.id]
      })

      # Send the same system message event twice
      token = "[broadcast:#{Ecto.UUID.generate()}]"

      sent =
        event(:message_sent, %{
          conversation_id: conversation_id,
          message_id: Ecto.UUID.generate(),
          sender_id: user_1.id,
          content: "System note #{token}",
          message_type: :system,
          sent_at: now()
        })

      # Send same event twice
      dispatch(sent)
      dispatch(sent)

      # system_notes should have exactly 1 key (idempotent merge)
      summary =
        Repo.one(
          from(s in ConversationSummary,
            where: s.conversation_id == ^conversation_id and s.user_id == ^user_1.id
          )
        )

      assert map_size(summary.system_notes) == 1
      assert Map.has_key?(summary.system_notes, token)
    end
  end

  # Same gap as #1311, different context: the tests above hand a native %Event{} to
  # the projection, while production stages it into oban_jobs.args first. These use
  # the real constructors and cross that boundary, so a %DateTime{} arriving as an
  # ISO string fails here instead of in prod.
  describe "events crossing the outbox boundary" do
    setup do
      user_1 = user_fixture(name: "Alice Smith")
      user_2 = user_fixture(name: "Bob Jones")
      conversation_id = Ecto.UUID.generate()

      dispatch(:conversation_created, %{
        conversation_id: conversation_id,
        type: :direct,
        provider_id: Ecto.UUID.generate(),
        participant_ids: [user_1.id, user_2.id]
      })

      {:ok, conversation_id: conversation_id, user_1: user_1, user_2: user_2}
    end

    test "message_sent keeps sent_at a DateTime for latest_message_at", ctx do
      sent_at = now()

      Events.message_sent(
        ctx.conversation_id,
        Ecto.UUID.generate(),
        ctx.user_1.id,
        "Hello Bob!",
        :text,
        sent_at
      )
      |> through_outbox()
      |> dispatch()

      summary = summary_for(ctx.conversation_id, ctx.user_2.id)
      assert summary.latest_message_at == sent_at
    end

    test "message_sent with a broadcast token stamps system_notes", ctx do
      token = "[broadcast:#{Ecto.UUID.generate()}]"

      Events.message_sent(
        ctx.conversation_id,
        Ecto.UUID.generate(),
        ctx.user_1.id,
        "System note #{token}",
        :system,
        now()
      )
      |> through_outbox()
      |> dispatch()

      summary = summary_for(ctx.conversation_id, ctx.user_2.id)
      assert Map.has_key?(summary.system_notes, token)
    end

    test "messages_read keeps read_at a DateTime for last_read_at", ctx do
      read_at = now()

      Events.messages_read(ctx.conversation_id, ctx.user_2.id, read_at)
      |> through_outbox()
      |> dispatch()

      summary = summary_for(ctx.conversation_id, ctx.user_2.id)
      assert summary.last_read_at == read_at
      assert summary.unread_count == 0
    end
  end

  # `:conversation_created` was the one event with no outbox round-trip: every other
  # call site here builds the %Event{} in memory, so `:type` crossing serialization was
  # never exercised. Both denormalised names are asserted alongside the type because a
  # resolver keyed on the wrong form of `:type` falls to its catch-all and returns nil
  # rather than failing — that is bug #892's shape.
  @created_type_cases [
    {:direct, nil, "Bob Jones"},
    {:program_broadcast, "Forest Friends", nil}
  ]

  describe "conversation_created crossing the outbox boundary" do
    for {type, expected_program_name, expected_other_name} <- @created_type_cases do
      test "#{type} survives serialization and still resolves its names" do
        type = unquote(type)
        expected_program_name = unquote(expected_program_name)
        expected_other_name = unquote(expected_other_name)

        provider = insert(:provider_profile_schema)
        program = insert(:program_schema, provider_id: provider.id, title: "Forest Friends")
        user_1 = user_fixture(name: "Alice Smith")
        user_2 = user_fixture(name: "Bob Jones")
        conversation_id = Ecto.UUID.generate()

        Events.conversation_created(
          conversation_id,
          type,
          provider.id,
          [user_1.id, user_2.id],
          program.id
        )
        |> through_outbox()
        |> dispatch()

        summary = summary_for(conversation_id, user_1.id)

        assert summary.conversation_type == type,
               "expected #{inspect(type)} to survive the outbox, got #{inspect(summary.conversation_type)}"

        assert summary.program_name == expected_program_name
        assert summary.other_participant_name == expected_other_name
      end
    end
  end

  describe "handle messages_read event" do
    test "sets unread_count to 0 and updates last_read_at for the user" do
      user_1 = user_fixture(name: "Alice Smith")
      user_2 = user_fixture(name: "Bob Jones")

      conversation_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()

      # Create conversation + send a message so user_2 has unread
      dispatch(:conversation_created, %{
        conversation_id: conversation_id,
        type: :direct,
        provider_id: provider_id,
        participant_ids: [user_1.id, user_2.id]
      })

      dispatch(:message_sent, %{
        conversation_id: conversation_id,
        message_id: Ecto.UUID.generate(),
        sender_id: user_1.id,
        content: "Unread message",
        sent_at: now()
      })

      # Verify user_2 has unread_count = 1
      summary =
        Repo.one(
          from(s in ConversationSummary,
            where: s.conversation_id == ^conversation_id and s.user_id == ^user_2.id
          )
        )

      assert summary.unread_count == 1

      # Now user_2 reads messages
      read_at = DateTime.add(now(), 10, :second)

      dispatch(:messages_read, %{
        conversation_id: conversation_id,
        user_id: user_2.id,
        read_at: read_at
      })

      # Verify unread_count is now 0
      summary =
        Repo.one(
          from(s in ConversationSummary,
            where: s.conversation_id == ^conversation_id and s.user_id == ^user_2.id
          )
        )

      assert summary.unread_count == 0
      assert summary.last_read_at == read_at
    end
  end

  describe "handle conversations_archived event" do
    test "sets archived_at for all participants across multiple conversations" do
      user_1 = user_fixture(name: "Alice Smith")
      user_2 = user_fixture(name: "Bob Jones")
      provider_id = Ecto.UUID.generate()
      archived_at = now()

      conv_1_id = Ecto.UUID.generate()
      conv_2_id = Ecto.UUID.generate()

      # Create two conversations
      for conv_id <- [conv_1_id, conv_2_id] do
        dispatch(:conversation_created, %{
          conversation_id: conv_id,
          type: :direct,
          provider_id: provider_id,
          participant_ids: [user_1.id, user_2.id]
        })
      end

      # Built through the real constructor, not a literal payload: a hand-written map
      # here is what let the producer stop sending archived_at without any test noticing.
      [conv_1_id, conv_2_id]
      |> Events.conversations_archived(:program_ended, 2, archived_at)
      |> dispatch()

      # All 4 summary rows (2 per conversation) should have archived_at set
      summaries =
        Repo.all(
          from(s in ConversationSummary,
            where: s.conversation_id in ^[conv_1_id, conv_2_id]
          )
        )

      assert length(summaries) == 4
      assert Enum.all?(summaries, fn s -> s.archived_at == archived_at end)
    end

    test "falls back to occurred_at for an event staged before archived_at was on the payload" do
      user = user_fixture(name: "Alice Smith")
      conversation_id = Ecto.UUID.generate()

      dispatch(:conversation_created, %{
        conversation_id: conversation_id,
        type: :direct,
        provider_id: Ecto.UUID.generate(),
        participant_ids: [user.id]
      })

      # The pre-#1216 payload shape, which can still be sitting in the queue across the
      # deploy. A literal map is right here: the point is a payload the constructor can
      # no longer build.
      event =
        event(:conversations_archived, %{conversation_ids: [conversation_id], reason: :program_ended, count: 1},
          entity_id: "bulk_archive_#{System.unique_integer([:positive])}"
        )

      dispatch(event)

      summary = Repo.one(from(s in ConversationSummary, where: s.conversation_id == ^conversation_id))

      assert summary.archived_at == DateTime.truncate(event.occurred_at, :second),
             "a legacy event must still archive the row rather than dead-letter the job"
    end
  end

  describe "handle message_data_anonymized event" do
    test "updates other_participant_name to 'Deleted User' for the anonymized user" do
      user_1 = user_fixture(name: "Alice Smith")
      user_2 = user_fixture(name: "Bob Jones")

      conversation_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()

      # Create conversation
      dispatch(:conversation_created, %{
        conversation_id: conversation_id,
        type: :direct,
        provider_id: provider_id,
        participant_ids: [user_1.id, user_2.id]
      })

      # Verify initial names are correct
      summary_1 =
        Repo.one(
          from(s in ConversationSummary,
            where: s.conversation_id == ^conversation_id and s.user_id == ^user_1.id
          )
        )

      assert summary_1.other_participant_name == "Bob Jones"

      # Anonymize user_2
      dispatch(
        :message_data_anonymized,
        %{user_id: user_2.id},
        entity_type: :user,
        entity_id: user_2.id
      )

      # user_1's summary should now show "Deleted User" as the other participant
      summary_1 =
        Repo.one(
          from(s in ConversationSummary,
            where: s.conversation_id == ^conversation_id and s.user_id == ^user_1.id
          )
        )

      assert summary_1.other_participant_name == "Deleted User"

      # user_2's summary should remain unchanged (their own name display is not affected)
      summary_2 =
        Repo.one(
          from(s in ConversationSummary,
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

      insert_conversation(id: conversation_id, type: :direct, provider_id: provider.id)

      # Insert participants: owner first, then parent, then staff
      insert_participant(conversation_id, user_id: provider.identity_id, joined_at: now())
      insert_participant(conversation_id, user_id: parent_user.id, joined_at: now())
      insert_participant(conversation_id, user_id: staff_user.id, joined_at: now())

      # Rebuild projection
      assert :ok = ConversationSummaries.rebuild(@test_server_name)

      # All 3 participants should have a summary row
      all_summaries =
        Repo.all(
          from(s in ConversationSummary,
            where: s.conversation_id == ^conversation_id
          )
        )

      assert length(all_summaries) == 3

      # Staff should have a summary row (also verifiable via the list helper)
      staff_summaries = list_summaries_for_user(staff_user.id)
      assert length(staff_summaries) == 1
      staff_summary = hd(staff_summaries)
      assert staff_summary.conversation_id == conversation_id
      assert staff_summary.conversation_type == :direct
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

      insert_conversation(id: conversation_id, type: :direct, provider_id: provider.id)

      # Use distinct joined_at timestamps to guarantee ordering via preload_order
      insert_participant(conversation_id, user_id: parent_user.id, joined_at: now())
      insert_participant(conversation_id, user_id: provider.identity_id, joined_at: DateTime.add(now(), 1, :second))
      insert_participant(conversation_id, user_id: staff_user.id, joined_at: DateTime.add(now(), 2, :second))

      assert :ok = ConversationSummaries.rebuild(@test_server_name)

      staff_summary =
        Repo.one(
          from(s in ConversationSummary,
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

      insert_conversation(id: conversation_id, type: :direct, provider_id: provider.id)

      for {uid, ts} <- [{parent.id, now()}, {provider_user.id, DateTime.add(now(), 1, :second)}] do
        insert_participant(conversation_id, user_id: uid, joined_at: ts)
      end

      # Seed an existing message so the new participant's summary back-fills
      # last-message data and unread_count
      insert_message(conversation_id, sender_id: parent.id, content: "Hi there")

      # Add staff participant in write model — projection event follows
      insert_participant(conversation_id, user_id: staff.id, joined_at: DateTime.add(now(), 2, :second))

      dispatch(:participant_added, %{
        conversation_id: conversation_id,
        participant_user_ids: [staff.id],
        source: :later_assignment
      })

      summary =
        Repo.one(
          from(s in ConversationSummary,
            where: s.conversation_id == ^conversation_id and s.user_id == ^staff.id
          )
        )

      assert summary != nil, "staff summary row must exist after :participant_added"
      assert summary.conversation_type == :direct
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

      insert_conversation(id: conversation_id, type: :direct, provider_id: provider.id)
      insert_participant(conversation_id, user_id: parent.id, joined_at: now())
      insert_participant(conversation_id, user_id: staff.id, joined_at: DateTime.add(now(), 1, :second))

      added =
        event(:participant_added, %{
          conversation_id: conversation_id,
          participant_user_ids: [staff.id],
          source: :later_assignment
        })

      dispatch(added)

      # Staff reads the conversation: simulate by setting last_read_at + zeroing unread
      read_at = now()

      {1, _} =
        Repo.update_all(
          from(s in ConversationSummary,
            where: s.conversation_id == ^conversation_id and s.user_id == ^staff.id
          ),
          set: [last_read_at: read_at, unread_count: 0]
        )

      # Replay the same event
      dispatch(added)

      summary =
        Repo.one(
          from(s in ConversationSummary,
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

      insert_conversation(id: conversation_id, type: :direct, provider_id: provider.id)

      for {uid, ts} <- [
            {parent.id, now()},
            {staff_a.id, DateTime.add(now(), 1, :second)},
            {staff_b.id, DateTime.add(now(), 2, :second)}
          ] do
        insert_participant(conversation_id, user_id: uid, joined_at: ts)
      end

      dispatch(:participant_added, %{
        conversation_id: conversation_id,
        participant_user_ids: [staff_a.id, staff_b.id],
        source: :initial_staff
      })

      summaries =
        Repo.all(
          from(s in ConversationSummary,
            where:
              s.conversation_id == ^conversation_id and
                s.user_id in ^[staff_a.id, staff_b.id],
            order_by: s.user_id
          )
        )

      assert length(summaries) == 2
      assert Enum.all?(summaries, &(&1.participant_count == 3))
      assert Enum.all?(summaries, &(&1.conversation_type == :direct))
    end

    test "inserts row for broadcast conversation with nil other_participant_name" do
      _ = :sys.get_state(@test_server_name)

      provider = insert(:provider_profile_schema)
      staff = user_fixture(name: "Staff Late")

      conversation_id = Ecto.UUID.generate()

      insert_conversation(id: conversation_id, type: :program_broadcast, provider_id: provider.id)
      insert_participant(conversation_id, user_id: staff.id, joined_at: now())

      dispatch(:participant_added, %{
        conversation_id: conversation_id,
        participant_user_ids: [staff.id],
        source: :later_assignment
      })

      summary =
        Repo.one(
          from(s in ConversationSummary,
            where: s.conversation_id == ^conversation_id and s.user_id == ^staff.id
          )
        )

      assert summary != nil
      assert summary.conversation_type == :program_broadcast
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

      dispatch(:conversation_created, %{
        conversation_id: conversation_id,
        type: :direct,
        provider_id: provider_id,
        participant_ids: [user_1.id, staff.id]
      })

      dispatch(:participant_removed, %{
        conversation_id: conversation_id,
        participant_user_ids: [staff.id],
        source: :staff_unassignment
      })

      staff_summary =
        Repo.one(
          from(s in ConversationSummary,
            where: s.conversation_id == ^conversation_id and s.user_id == ^staff.id
          )
        )

      assert staff_summary != nil
      assert staff_summary.archived_at != nil

      # Non-removed users keep their row intact
      user_1_summary =
        Repo.one(
          from(s in ConversationSummary,
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

      dispatch(:conversation_created, %{
        conversation_id: conversation_id,
        type: :direct,
        provider_id: provider_id,
        participant_ids: [user_1.id, staff.id]
      })

      removed =
        event(:participant_removed, %{
          conversation_id: conversation_id,
          participant_user_ids: [staff.id],
          source: :staff_unassignment
        })

      dispatch(removed)

      first =
        Repo.one(
          from(s in ConversationSummary,
            where: s.conversation_id == ^conversation_id and s.user_id == ^staff.id,
            select: s.archived_at
          )
        )

      # Replay later — the second archived_at would differ if the handler
      # blindly overwrote. COALESCE keeps the original.
      Process.sleep(1_100)

      dispatch(removed)

      second =
        Repo.one(
          from(s in ConversationSummary,
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

      dispatch(:conversation_created, %{
        conversation_id: conversation_id,
        type: :direct,
        provider_id: provider_id,
        participant_ids: [user_1.id, staff_a.id, staff_b.id]
      })

      dispatch(:participant_removed, %{
        conversation_id: conversation_id,
        participant_user_ids: [staff_a.id, staff_b.id],
        source: :staff_unassignment
      })

      archived_count =
        Repo.aggregate(
          from(s in ConversationSummary,
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
        event(:conversation_created, %{
          conversation_id: conversation_id,
          participant_ids: [user_1.id, user_2.id],
          type: :direct,
          provider_id: provider_id,
          program_id: nil,
          subject: nil
        })

      assert :ok = ConversationSummaries.project(event)

      # Projecting is not a message to this process, so its bootstrap state is untouched.
      assert %{bootstrapped: true, retry_count: 0} = :sys.get_state(pid)
    end
  end

  # ── Seed + dispatch helpers ────────────────────────────────────────────────

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp summary_for(conversation_id, user_id) do
    Repo.one!(
      from(s in ConversationSummary,
        where: s.conversation_id == ^conversation_id and s.user_id == ^user_id
      )
    )
  end

  defp insert_conversation(attrs) do
    Repo.insert!(struct!(Conversation, Keyword.put_new(attrs, :id, Ecto.UUID.generate())))
  end

  defp insert_participant(conversation_id, attrs) do
    attrs =
      attrs
      |> Keyword.put_new(:id, Ecto.UUID.generate())
      |> Keyword.put(:conversation_id, conversation_id)

    Repo.insert!(struct!(Participant, attrs))
  end

  defp insert_message(conversation_id, attrs) do
    ts = Keyword.get(attrs, :inserted_at, now())

    attrs =
      attrs
      |> Keyword.put_new(:id, Ecto.UUID.generate())
      |> Keyword.put(:conversation_id, conversation_id)
      |> Keyword.put_new(:message_type, :text)
      |> Keyword.put_new(:inserted_at, ts)
      |> Keyword.put_new(:updated_at, ts)

    Repo.insert!(struct!(Message, attrs))
  end

  # Stops the shared server and starts a fresh one so it re-runs bootstrap from
  # the write tables; blocks on :sys.get_state until bootstrap completes. Keeps
  # the bootstrap sync path (a distinct, per-test pid) separate from dispatch/1's
  # module-server sync.
  defp restart_for_bootstrap(id) do
    stop_supervised!(ConversationSummaries)
    name = :"#{id}_#{System.unique_integer([:positive])}"
    pid = start_supervised!({ConversationSummaries, name: name}, id: id)
    :sys.get_state(pid)
    pid
  end

  # Builds a messaging integration event, defaulting the entity to
  # (:conversation, payload.conversation_id); override via :entity_type/:entity_id.
  defp event(event_type, payload, opts \\ []) do
    entity_type = Keyword.get(opts, :entity_type, :conversation)
    entity_id = Keyword.get(opts, :entity_id, Map.get(payload, :conversation_id))
    Event.new(event_type, :messaging, entity_type, entity_id, payload)
  end

  # Projects in the test process, exactly as the delivery job does — no broadcast,
  # no mailbox fence, the projection GenServer is not in this path.
  defp dispatch(%Event{} = event) do
    ConversationSummaries.project(event)
    event
  end

  # Convenience: build and dispatch a single-shot event.
  defp dispatch(event_type, payload, opts \\ []) when is_atom(event_type) do
    event_type |> event(payload, opts) |> dispatch()
  end

  # Helper to create users with specific names
  defp user_fixture(attrs) do
    KlassHero.AccountsFixtures.user_fixture(attrs)
  end

  defp list_summaries_for_user(user_id) do
    Repo.all(
      from(s in ConversationSummary,
        where: s.user_id == ^user_id
      )
    )
  end
end
