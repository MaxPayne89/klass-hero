defmodule KlassHero.Messaging.BroadcastToProgramTest do
  use KlassHero.DataCase, async: false

  import KlassHero.EventTestHelper
  import KlassHero.Factory

  alias KlassHero.Accounts.Scope
  alias KlassHero.AccountsFixtures
  alias KlassHero.Messaging.Adapters.Driven.Persistence.Repositories.ProgramStaffParticipantRepository
  alias KlassHero.Messaging.Adapters.Driven.Projections.ConversationSummaries
  alias KlassHero.Messaging.BroadcastToProgram
  alias KlassHero.Messaging.Conversation
  alias KlassHero.Messaging.Message
  alias KlassHero.Provider.ProviderProfile

  setup do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)
    scope = build_scope_with_provider(provider)
    %{provider: provider, program: program, scope: scope}
  end

  describe "execute/4" do
    test "creates broadcast conversation and message with enrolled parents", ctx do
      %{program: program, scope: scope} = ctx
      enroll_parent(program, status: "confirmed")
      enroll_parent(program, status: "pending")

      assert {:ok, conversation, message, recipient_count} =
               BroadcastToProgram.execute(scope, program.id, "Important announcement!")

      assert %Conversation{} = conversation
      assert conversation.type == :program_broadcast
      assert conversation.program_id == program.id

      assert %Message{} = message
      assert message.content == "Important announcement!"

      assert recipient_count == 2
    end

    test "includes subject when provided", %{program: program, scope: scope} do
      enroll_parent(program)

      assert {:ok, conversation, _message, _count} =
               BroadcastToProgram.execute(
                 scope,
                 program.id,
                 "Content",
                 subject: "Schedule Change"
               )

      assert conversation.subject == "Schedule Change"
    end

    # Provider tiers removed (ADR-0004): no entitlement gate on broadcasts.
    test "any provider can broadcast (former starter tier included)", %{
      program: program,
      scope: scope
    } do
      enroll_parent(program)

      assert {:ok, _conversation, _message, _recipient_count} =
               BroadcastToProgram.execute(scope, program.id, "Message")
    end

    test "returns no_enrollments error when no parents enrolled", %{program: program, scope: scope} do
      assert {:error, :no_enrollments} =
               BroadcastToProgram.execute(scope, program.id, "Message")
    end

    test "excludes cancelled and completed enrollments", %{program: program, scope: scope} do
      enroll_parent(program, status: "confirmed")
      enroll_parent(program, status: "cancelled")
      enroll_parent(program, status: "completed")

      assert {:ok, _conversation, _message, recipient_count} =
               BroadcastToProgram.execute(scope, program.id, "Message")

      assert recipient_count == 1
    end

    test "provider can broadcast", %{program: program, scope: scope} do
      enroll_parent(program)

      assert {:ok, _conversation, _message, _count} =
               BroadcastToProgram.execute(scope, program.id, "Message")
    end
  end

  describe "staff auto-inclusion in broadcast" do
    test "adds assigned staff as participants alongside parents", ctx do
      %{provider: provider, program: program, scope: scope} = ctx
      enroll_parent(program)

      staff_user = AccountsFixtures.user_fixture()

      ProgramStaffParticipantRepository.upsert_active(%{
        provider_id: provider.id,
        program_id: program.id,
        staff_user_id: staff_user.id
      })

      assert {:ok, conversation, _message, _count} =
               BroadcastToProgram.execute(scope, program.id, "Important update!")

      assert KlassHero.Messaging.participant?(conversation.id, staff_user.id)
    end

    test "does not duplicate owner when owner is also assigned as staff", ctx do
      %{provider: provider, program: program, scope: scope} = ctx
      enroll_parent(program)

      # Assign the broadcasting user as staff too.
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
    test "second broadcast on the same program reuses the conversation and persists both messages",
         %{program: program, scope: scope} do
      enroll_parent(program)

      assert {:ok, first_conv, first_msg, 1} =
               BroadcastToProgram.execute(scope, program.id, "First announcement")

      assert {:ok, second_conv, second_msg, 1} =
               BroadcastToProgram.execute(scope, program.id, "Second announcement")

      assert second_conv.id == first_conv.id
      refute second_msg.id == first_msg.id

      # Sender stays a single participant — no duplicate insert.
      assert KlassHero.Messaging.participant?(first_conv.id, scope.user.id)

      sender_rows =
        first_conv.id
        |> KlassHero.Messaging.list_participants()
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

    test "persists attachments alongside the broadcast message", %{program: program, scope: scope} do
      enroll_parent(program)

      assert {:ok, _conversation, message, _count} =
               BroadcastToProgram.execute(scope, program.id, "Look at this!", attachments: [@photo])

      assert length(message.attachments) == 1
      assert hd(message.attachments).original_filename == "announcement.jpg"
    end

    test "attachment-only broadcast persists nil content", %{program: program, scope: scope} do
      enroll_parent(program)

      for content <- ["", "   "] do
        assert {:ok, _conversation, message, _count} =
                 BroadcastToProgram.execute(scope, program.id, content, attachments: [@photo]),
               "expected attachment-only broadcast to succeed for content #{inspect(content)}"

        assert message.content == nil,
               "expected content nil for attachment-only broadcast, got #{inspect(message.content)}"
      end
    end

    test "surfaces SendMessage validation errors", %{program: program, scope: scope} do
      enroll_parent(program)

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

    test "publishes :message_sent with conversation, sender, and content", %{
      program: program,
      scope: scope
    } do
      enroll_parent(program)

      assert {:ok, conversation, message, _count} =
               BroadcastToProgram.execute(scope, program.id, "Announcement")

      assert_event_published(:message_sent, %{
        conversation_id: conversation.id,
        message_id: message.id,
        sender_id: scope.user.id,
        content: "Announcement"
      })
    end

    test "does not publish :broadcast_sent", %{program: program, scope: scope} do
      enroll_parent(program)

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

    test "first broadcast emits :participant_added with source :broadcast_setup carrying sender + parent user_ids",
         %{program: program, scope: scope} do
      %{user: parent1_user} = enroll_parent(program)
      %{user: parent2_user} = enroll_parent(program)

      assert {:ok, conversation, _msg, _count} =
               BroadcastToProgram.execute(scope, program.id, "Hi")

      event =
        get_published_integration_events()
        |> Enum.find(
          &match?(
            %{event_type: :participant_added, payload: %{source: "broadcast_setup"}},
            &1
          )
        )

      assert event,
             "expected a :participant_added integration event with source :broadcast_setup to be published"

      assert event.entity_id == conversation.id

      assert Enum.sort(event.payload.participant_user_ids) ==
               Enum.sort([scope.user.id, parent1_user.id, parent2_user.id])
    end

    test "re-broadcast on existing conversation with same participants emits NO :broadcast_setup event",
         %{program: program, scope: scope} do
      enroll_parent(program)

      assert {:ok, _, _, _} = BroadcastToProgram.execute(scope, program.id, "first")

      clear_integration_events()

      assert {:ok, _, _, _} = BroadcastToProgram.execute(scope, program.id, "second")

      refute Enum.any?(
               get_published_integration_events(),
               &match?(
                 %{event_type: :participant_added, payload: %{source: "broadcast_setup"}},
                 &1
               )
             ),
             "expected no :broadcast_setup event on re-broadcast when participants are unchanged"
    end

    test "re-broadcast that adds a NEW enrolled parent emits :broadcast_setup with only the new user_id",
         %{program: program, scope: scope} do
      enroll_parent(program)

      assert {:ok, _, _, _} = BroadcastToProgram.execute(scope, program.id, "first")

      clear_integration_events()

      # New parent enrolled between broadcasts.
      %{user: parent2_user} = enroll_parent(program)

      assert {:ok, _, _, _} = BroadcastToProgram.execute(scope, program.id, "second")

      event =
        get_published_integration_events()
        |> Enum.find(
          &match?(
            %{event_type: :participant_added, payload: %{source: "broadcast_setup"}},
            &1
          )
        )

      assert event,
             "expected a :participant_added event with source :broadcast_setup for the newly-enrolled parent"

      assert event.payload.participant_user_ids == [parent2_user.id]
    end

    test "sender and each parent see broadcast in inbox after projection runs (no server restart)",
         %{program: program, scope: scope} do
      %{user: parent1_user} = enroll_parent(program)
      %{user: parent2_user} = enroll_parent(program)

      assert {:ok, conversation, _msg, _count} =
               BroadcastToProgram.execute(scope, program.id, "Important")

      event =
        get_published_integration_events()
        |> Enum.find(
          &match?(
            %{event_type: :participant_added, payload: %{source: "broadcast_setup"}},
            &1
          )
        )

      assert event, "expected :broadcast_setup event to be dispatched"

      # Drive the projection directly — deterministic, avoids PubSub timing.
      ConversationSummaries.handle_event(:participant_added, event)

      for user_id <- [scope.user.id, parent1_user.id, parent2_user.id] do
        {:ok, summaries, _has_more} = KlassHero.Messaging.list_conversation_summaries_for_user(user_id, [])

        assert Enum.any?(summaries, &(&1.conversation_id == conversation.id)),
               "expected user #{user_id} to see broadcast conversation #{conversation.id} in inbox; " <>
                 "got #{inspect(Enum.map(summaries, & &1.conversation_id))}"
      end
    end
  end

  describe "authorization" do
    test "rejects every unclaimable target with :not_found", %{scope: scope} do
      %{provider: foreign_provider, program: foreign_program} = insert_foreign_program()

      cases = [
        {"another provider's program", foreign_program.id, []},
        {"an unknown program id", Ecto.UUID.generate(), []},
        {"a malformed program id", "not-a-uuid", []},
        {"a provider_id the scope neither owns nor staffs", foreign_program.id,
         [provider_id: foreign_provider.id, skip_entitlement_check: true]}
      ]

      for {label, program_id, opts} <- cases do
        assert {:error, :not_found} = BroadcastToProgram.execute(scope, program_id, "Leak?", opts),
               "expected :not_found for #{label}"
      end
    end

    # Separate from the table above on purpose: `assert` inside a `for` raises on
    # the first failure, so trailing invariants would go unchecked whenever an
    # earlier case regressed — exactly when they matter most.
    test "rejected broadcasts leave no trace", %{scope: scope} do
      %{provider: foreign_provider, program: foreign_program} = insert_foreign_program()

      assert {:error, :not_found} = BroadcastToProgram.execute(scope, foreign_program.id, "Leak?")

      assert {:error, :not_found} =
               KlassHero.Messaging.find_active_broadcast_for_program(foreign_provider.id, foreign_program.id)

      assert Repo.aggregate(Message, :count) == 0,
             "no message may be persisted for a rejected broadcast"
    end

    test "allows active staff to broadcast for their provider", %{provider: provider, program: program} do
      staff_scope = build_staff_scope(provider)
      enroll_parent(program)

      assert {:ok, _conversation, _message, 1} =
               BroadcastToProgram.execute(staff_scope, program.id, "From staff",
                 provider_id: provider.id,
                 skip_entitlement_check: true
               )
    end

    test "returns missing_provider_id when neither scope nor opts resolve a provider" do
      scope = %Scope{user: AccountsFixtures.user_fixture(), roles: [], provider: nil, parent: nil}

      assert {:error, :missing_provider_id} =
               BroadcastToProgram.execute(scope, Ecto.UUID.generate(), "Hi")
    end
  end

  # A program owned by somebody else, with a parent enrolled so that a rejection
  # can't be mistaken for :no_enrollments.
  defp insert_foreign_program do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)
    enroll_parent(program)

    %{provider: provider, program: program}
  end

  # Enrolls a fresh parent (backed by a real user for the FK) into the program.
  # Returns the created %{user, parent}.
  defp enroll_parent(program, opts \\ []) do
    status = Keyword.get(opts, :status, "confirmed")
    user = AccountsFixtures.user_fixture()
    parent = insert(:parent_profile_schema, identity_id: user.id)

    insert(:enrollment_schema, program_id: program.id, parent_id: parent.id, status: status)

    %{user: user, parent: parent}
  end

  defp build_scope_with_provider(provider_schema) do
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
      business_name: "Test Provider"
    }

    %Scope{
      user: user,
      roles: [:provider],
      provider: provider_profile,
      parent: nil
    }
  end

  # A staff scope has no `provider` — the acting provider is carried in opts and
  # must be authorised against an active staff row (as StaffBroadcastLive does).
  defp build_staff_scope(provider_schema) do
    user = AccountsFixtures.user_fixture()
    staff = insert(:staff_member_schema, provider_id: provider_schema.id, user_id: user.id, active: true)

    %Scope{
      user: user,
      roles: [:staff],
      provider: nil,
      parent: nil,
      staff_member: staff
    }
  end
end
