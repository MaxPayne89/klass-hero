defmodule KlassHero.Messaging.Application.Commands.BroadcastToProgramTest do
  use KlassHero.DataCase, async: false

  import KlassHero.EventTestHelper
  import KlassHero.Factory

  alias KlassHero.Accounts.Scope
  alias KlassHero.AccountsFixtures
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.ConversationSummariesRepository
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.ParticipantRepository
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.ProgramStaffParticipantRepository
  alias KlassHero.Messaging.Adapters.Driven.Projections.ConversationSummaries
  alias KlassHero.Messaging.Application.Commands.BroadcastToProgram
  alias KlassHero.Messaging.Domain.Models.{Conversation, Message}
  alias KlassHero.Provider.Domain.Models.ProviderProfile

  describe "execute/4" do
    test "creates broadcast conversation and message with enrolled parents" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema)
      scope = build_scope_with_provider(provider, :professional)

      # Create parents with real users to satisfy FK constraint
      parent_user1 = AccountsFixtures.user_fixture()
      parent_user2 = AccountsFixtures.user_fixture()
      parent1 = insert(:parent_profile_schema, identity_id: parent_user1.id)
      parent2 = insert(:parent_profile_schema, identity_id: parent_user2.id)

      insert(:enrollment_schema,
        program_id: program.id,
        parent_id: parent1.id,
        status: "confirmed"
      )

      insert(:enrollment_schema,
        program_id: program.id,
        parent_id: parent2.id,
        status: "pending"
      )

      assert {:ok, conversation, message, recipient_count} =
               BroadcastToProgram.execute(scope, program.id, "Important announcement!")

      assert %Conversation{} = conversation
      assert conversation.type == :program_broadcast
      assert conversation.program_id == program.id

      assert %Message{} = message
      assert message.content == "Important announcement!"

      assert recipient_count == 2
    end

    test "includes subject when provided" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema)
      scope = build_scope_with_provider(provider, :professional)

      parent_user = AccountsFixtures.user_fixture()
      parent = insert(:parent_profile_schema, identity_id: parent_user.id)

      insert(:enrollment_schema,
        program_id: program.id,
        parent_id: parent.id,
        status: "confirmed"
      )

      assert {:ok, conversation, _message, _count} =
               BroadcastToProgram.execute(
                 scope,
                 program.id,
                 "Content",
                 subject: "Schedule Change"
               )

      assert conversation.subject == "Schedule Change"
    end

    test "returns not_entitled error for starter tier provider" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema)
      scope = build_scope_with_provider(provider, :starter)

      parent = insert(:parent_profile_schema)

      insert(:enrollment_schema,
        program_id: program.id,
        parent_id: parent.id,
        status: "confirmed"
      )

      assert {:error, :not_entitled} =
               BroadcastToProgram.execute(scope, program.id, "Message")
    end

    test "returns no_enrollments error when no parents enrolled" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema)
      scope = build_scope_with_provider(provider, :professional)

      assert {:error, :no_enrollments} =
               BroadcastToProgram.execute(scope, program.id, "Message")
    end

    test "excludes cancelled and completed enrollments" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema)
      scope = build_scope_with_provider(provider, :professional)

      active_user = AccountsFixtures.user_fixture()
      cancelled_user = AccountsFixtures.user_fixture()
      completed_user = AccountsFixtures.user_fixture()
      active_parent = insert(:parent_profile_schema, identity_id: active_user.id)
      cancelled_parent = insert(:parent_profile_schema, identity_id: cancelled_user.id)
      completed_parent = insert(:parent_profile_schema, identity_id: completed_user.id)

      insert(:enrollment_schema,
        program_id: program.id,
        parent_id: active_parent.id,
        status: "confirmed"
      )

      insert(:enrollment_schema,
        program_id: program.id,
        parent_id: cancelled_parent.id,
        status: "cancelled"
      )

      insert(:enrollment_schema,
        program_id: program.id,
        parent_id: completed_parent.id,
        status: "completed"
      )

      assert {:ok, _conversation, _message, recipient_count} =
               BroadcastToProgram.execute(scope, program.id, "Message")

      assert recipient_count == 1
    end

    test "professional tier provider can broadcast" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema)
      scope = build_scope_with_provider(provider, :professional)

      parent_user = AccountsFixtures.user_fixture()
      parent = insert(:parent_profile_schema, identity_id: parent_user.id)

      insert(:enrollment_schema,
        program_id: program.id,
        parent_id: parent.id,
        status: "confirmed"
      )

      assert {:ok, _conversation, _message, _count} =
               BroadcastToProgram.execute(scope, program.id, "Message")
    end

    test "business_plus tier provider can broadcast" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema)
      scope = build_scope_with_provider(provider, :business_plus)

      parent_user = AccountsFixtures.user_fixture()
      parent = insert(:parent_profile_schema, identity_id: parent_user.id)

      insert(:enrollment_schema,
        program_id: program.id,
        parent_id: parent.id,
        status: "confirmed"
      )

      assert {:ok, _conversation, _message, _count} =
               BroadcastToProgram.execute(scope, program.id, "Message")
    end
  end

  describe "staff auto-inclusion in broadcast" do
    test "adds assigned staff as participants alongside parents" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      scope = build_scope_with_provider(provider, :professional)

      parent_user = AccountsFixtures.user_fixture()
      parent = insert(:parent_profile_schema, identity_id: parent_user.id)

      insert(:enrollment_schema,
        program_id: program.id,
        parent_id: parent.id,
        status: "confirmed"
      )

      staff_user = AccountsFixtures.user_fixture()

      ProgramStaffParticipantRepository.upsert_active(%{
        provider_id: provider.id,
        program_id: program.id,
        staff_user_id: staff_user.id
      })

      assert {:ok, conversation, _message, _count} =
               BroadcastToProgram.execute(scope, program.id, "Important update!")

      assert ParticipantRepository.is_participant?(conversation.id, staff_user.id)
    end

    test "does not duplicate owner when owner is also assigned as staff" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      scope = build_scope_with_provider(provider, :professional)

      parent_user = AccountsFixtures.user_fixture()
      parent = insert(:parent_profile_schema, identity_id: parent_user.id)

      insert(:enrollment_schema,
        program_id: program.id,
        parent_id: parent.id,
        status: "confirmed"
      )

      # Assign the broadcasting user as staff too
      ProgramStaffParticipantRepository.upsert_active(%{
        provider_id: provider.id,
        program_id: program.id,
        staff_user_id: scope.user.id
      })

      assert {:ok, _conversation, _message, _count} =
               BroadcastToProgram.execute(scope, program.id, "Update!")
    end
  end

  describe "execute/4 — follow-up broadcasts" do
    # Trigger: provider sends a second broadcast on a program they have already broadcast to
    # Why: get_or_create_broadcast_conversation reuses the existing conversation, so the
    #      sender is already a participant when execute_broadcast_transaction runs the
    #      participant adds. Pre-fix, the sender's add hit a unique constraint and rolled
    #      back the entire transaction, surfacing as a generic "Failed to send broadcast".
    # Outcome: both calls succeed, the same broadcast conversation is reused, both messages
    #          are persisted, no duplicate participant rows.
    test "second broadcast on the same program reuses the conversation and persists both messages" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema)
      scope = build_scope_with_provider(provider, :professional)

      parent_user = AccountsFixtures.user_fixture()
      parent = insert(:parent_profile_schema, identity_id: parent_user.id)

      insert(:enrollment_schema,
        program_id: program.id,
        parent_id: parent.id,
        status: "confirmed"
      )

      assert {:ok, first_conv, first_msg, 1} =
               BroadcastToProgram.execute(scope, program.id, "First announcement")

      assert {:ok, second_conv, second_msg, 1} =
               BroadcastToProgram.execute(scope, program.id, "Second announcement")

      assert second_conv.id == first_conv.id
      refute second_msg.id == first_msg.id

      # Sender stays a single participant — no duplicate insert
      assert ParticipantRepository.is_participant?(first_conv.id, scope.user.id)

      sender_rows =
        first_conv.id
        |> ParticipantRepository.list_for_conversation()
        |> Enum.filter(&(&1.user_id == scope.user.id))

      assert length(sender_rows) == 1
    end
  end

  describe "execute/4 — attachments" do
    @photo %{
      binary: "fake-image-bytes",
      filename: "announcement.jpg",
      content_type: "image/jpeg",
      size: 1_000
    }

    test "persists attachments alongside the broadcast message" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema)
      scope = build_scope_with_provider(provider, :professional)

      parent_user = AccountsFixtures.user_fixture()
      parent = insert(:parent_profile_schema, identity_id: parent_user.id)

      insert(:enrollment_schema,
        program_id: program.id,
        parent_id: parent.id,
        status: "confirmed"
      )

      assert {:ok, _conversation, message, _count} =
               BroadcastToProgram.execute(scope, program.id, "Look at this!", attachments: [@photo])

      assert length(message.attachments) == 1
      assert hd(message.attachments).original_filename == "announcement.jpg"
    end

    test "attachment-only broadcast persists nil content" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema)
      scope = build_scope_with_provider(provider, :professional)

      parent_user = AccountsFixtures.user_fixture()
      parent = insert(:parent_profile_schema, identity_id: parent_user.id)

      insert(:enrollment_schema,
        program_id: program.id,
        parent_id: parent.id,
        status: "confirmed"
      )

      for content <- ["", "   "] do
        assert {:ok, _conversation, message, _count} =
                 BroadcastToProgram.execute(scope, program.id, content, attachments: [@photo]),
               "expected attachment-only broadcast to succeed for content #{inspect(content)}"

        assert message.content == nil,
               "expected content nil for attachment-only broadcast, got #{inspect(message.content)}"
      end
    end

    test "surfaces SendMessage validation errors" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema)
      scope = build_scope_with_provider(provider, :professional)

      parent_user = AccountsFixtures.user_fixture()
      parent = insert(:parent_profile_schema, identity_id: parent_user.id)

      insert(:enrollment_schema,
        program_id: program.id,
        parent_id: parent.id,
        status: "confirmed"
      )

      too_many =
        for i <- 1..6 do
          %{binary: "x", filename: "p#{i}.jpg", content_type: "image/jpeg", size: 1_000}
        end

      pdf = [%{binary: "x", filename: "doc.pdf", content_type: "application/pdf", size: 1_000}]

      oversized =
        [%{binary: "x", filename: "huge.jpg", content_type: "image/jpeg", size: 11_000_000}]

      cases = [
        {too_many, :too_many_attachments},
        {pdf, :invalid_attachment_type},
        {oversized, :attachment_too_large}
      ]

      for {attachments, expected_error} <- cases do
        assert {:error, ^expected_error} =
                 BroadcastToProgram.execute(scope, program.id, "Hi", attachments: attachments),
               "expected #{inspect(expected_error)} for #{length(attachments)} files of type " <>
                 "#{inspect(Enum.map(attachments, & &1.content_type))}"
      end
    end
  end

  describe "execute/4 — event publishing" do
    setup do
      setup_test_events()
      :ok
    end

    test "publishes :message_sent with conversation, sender, and content" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema)
      scope = build_scope_with_provider(provider, :professional)

      parent_user = AccountsFixtures.user_fixture()
      parent = insert(:parent_profile_schema, identity_id: parent_user.id)

      insert(:enrollment_schema,
        program_id: program.id,
        parent_id: parent.id,
        status: "confirmed"
      )

      assert {:ok, conversation, message, _count} =
               BroadcastToProgram.execute(scope, program.id, "Announcement")

      assert_event_published(:message_sent, %{
        conversation_id: conversation.id,
        message_id: message.id,
        sender_id: scope.user.id,
        content: "Announcement"
      })
    end

    test "does not publish :broadcast_sent" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema)
      scope = build_scope_with_provider(provider, :professional)

      parent_user = AccountsFixtures.user_fixture()
      parent = insert(:parent_profile_schema, identity_id: parent_user.id)

      insert(:enrollment_schema,
        program_id: program.id,
        parent_id: parent.id,
        status: "confirmed"
      )

      assert {:ok, _conv, _msg, _count} =
               BroadcastToProgram.execute(scope, program.id, "Announcement")

      published_types = Enum.map(get_published_events(), & &1.event_type)
      refute :broadcast_sent in published_types
    end
  end

  describe "execute/4 — :participant_added event dispatch" do
    setup do
      setup_test_integration_events()
      :ok
    end

    test "first broadcast emits :participant_added with source :broadcast_setup carrying sender + parent user_ids" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      scope = build_scope_with_provider(provider, :professional)

      parent1_user = AccountsFixtures.user_fixture()
      parent2_user = AccountsFixtures.user_fixture()
      parent1 = insert(:parent_profile_schema, identity_id: parent1_user.id)
      parent2 = insert(:parent_profile_schema, identity_id: parent2_user.id)

      insert(:enrollment_schema,
        program_id: program.id,
        parent_id: parent1.id,
        status: "confirmed"
      )

      insert(:enrollment_schema,
        program_id: program.id,
        parent_id: parent2.id,
        status: "confirmed"
      )

      assert {:ok, conversation, _msg, _count} =
               BroadcastToProgram.execute(scope, program.id, "Hi")

      event =
        get_published_integration_events()
        |> Enum.find(
          &match?(
            %{event_type: :participant_added, payload: %{source: :broadcast_setup}},
            &1
          )
        )

      assert event,
             "expected a :participant_added integration event with source :broadcast_setup to be published"

      assert event.entity_id == conversation.id

      assert Enum.sort(event.payload.participant_user_ids) ==
               Enum.sort([scope.user.id, parent1_user.id, parent2_user.id])
    end

    test "re-broadcast on existing conversation with same participants emits NO :broadcast_setup event" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      scope = build_scope_with_provider(provider, :professional)

      parent_user = AccountsFixtures.user_fixture()
      parent = insert(:parent_profile_schema, identity_id: parent_user.id)

      insert(:enrollment_schema,
        program_id: program.id,
        parent_id: parent.id,
        status: "confirmed"
      )

      assert {:ok, _, _, _} = BroadcastToProgram.execute(scope, program.id, "first")

      clear_integration_events()

      assert {:ok, _, _, _} = BroadcastToProgram.execute(scope, program.id, "second")

      refute Enum.any?(
               get_published_integration_events(),
               &match?(
                 %{event_type: :participant_added, payload: %{source: :broadcast_setup}},
                 &1
               )
             ),
             "expected no :broadcast_setup event on re-broadcast when participants are unchanged"
    end

    test "re-broadcast that adds a NEW enrolled parent emits :broadcast_setup with only the new user_id" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      scope = build_scope_with_provider(provider, :professional)

      parent1_user = AccountsFixtures.user_fixture()
      parent1 = insert(:parent_profile_schema, identity_id: parent1_user.id)

      insert(:enrollment_schema,
        program_id: program.id,
        parent_id: parent1.id,
        status: "confirmed"
      )

      assert {:ok, _, _, _} = BroadcastToProgram.execute(scope, program.id, "first")

      clear_integration_events()

      # New parent enrolled between broadcasts
      parent2_user = AccountsFixtures.user_fixture()
      parent2 = insert(:parent_profile_schema, identity_id: parent2_user.id)

      insert(:enrollment_schema,
        program_id: program.id,
        parent_id: parent2.id,
        status: "confirmed"
      )

      assert {:ok, _, _, _} = BroadcastToProgram.execute(scope, program.id, "second")

      event =
        get_published_integration_events()
        |> Enum.find(
          &match?(
            %{event_type: :participant_added, payload: %{source: :broadcast_setup}},
            &1
          )
        )

      assert event,
             "expected a :participant_added event with source :broadcast_setup for the newly-enrolled parent"

      assert event.payload.participant_user_ids == [parent2_user.id]
    end

    test "sender and each parent see broadcast in inbox after projection runs (no server restart)" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      scope = build_scope_with_provider(provider, :professional)

      parent1_user = AccountsFixtures.user_fixture()
      parent2_user = AccountsFixtures.user_fixture()
      parent1 = insert(:parent_profile_schema, identity_id: parent1_user.id)
      parent2 = insert(:parent_profile_schema, identity_id: parent2_user.id)

      insert(:enrollment_schema,
        program_id: program.id,
        parent_id: parent1.id,
        status: "confirmed"
      )

      insert(:enrollment_schema,
        program_id: program.id,
        parent_id: parent2.id,
        status: "confirmed"
      )

      assert {:ok, conversation, _msg, _count} =
               BroadcastToProgram.execute(scope, program.id, "Important")

      event =
        get_published_integration_events()
        |> Enum.find(
          &match?(
            %{event_type: :participant_added, payload: %{source: :broadcast_setup}},
            &1
          )
        )

      assert event, "expected :broadcast_setup event to be dispatched"

      # Drive the projection directly — deterministic, avoids PubSub timing.
      ConversationSummaries.handle_event(:participant_added, event)

      for user_id <- [scope.user.id, parent1_user.id, parent2_user.id] do
        {:ok, summaries, _has_more} = ConversationSummariesRepository.list_for_user(user_id, [])

        assert Enum.any?(summaries, &(&1.conversation_id == conversation.id)),
               "expected user #{user_id} to see broadcast conversation #{conversation.id} in inbox; " <>
                 "got #{inspect(Enum.map(summaries, & &1.conversation_id))}"
      end
    end
  end

  defp build_scope_with_provider(provider_schema, tier) do
    user = AccountsFixtures.user_fixture()

    # Trigger: factory binds provider row to a throwaway unconfirmed user
    # Why: SendMessage's provider_owner? check compares scope.user.id against the
    #      provider row's identity_id; mismatch surfaces as :broadcast_reply_not_allowed
    # Outcome: rebind the row to our confirmed user so ownership checks pass
    {:ok, _} =
      provider_schema
      |> Ecto.Changeset.change(identity_id: user.id)
      |> KlassHero.Repo.update()

    provider_profile = %ProviderProfile{
      id: provider_schema.id,
      identity_id: user.id,
      business_name: "Test Provider",
      subscription_tier: tier
    }

    %Scope{
      user: user,
      roles: [:provider],
      provider: provider_profile,
      parent: nil
    }
  end
end
