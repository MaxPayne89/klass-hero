defmodule KlassHero.Messaging.SendMessageTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.AccountsFixtures
  alias KlassHero.Messaging.Conversation
  alias KlassHero.Messaging.Message
  alias KlassHero.Messaging.SendMessage
  alias KlassHero.Provider

  describe "execute/4" do
    test "sends message successfully for participant" do
      %{conversation: conversation, user: user} = conversation_with_participant()

      assert {:ok, message} =
               SendMessage.execute(conversation.id, user.id, "Hello, world!")

      assert %Message{} = message
      assert message.conversation_id == conversation.id
      assert message.sender_id == user.id
      assert message.content == "Hello, world!"
      assert message.message_type == :text
    end

    test "trims whitespace from content" do
      %{conversation: conversation, user: user} = conversation_with_participant()

      assert {:ok, message} =
               SendMessage.execute(conversation.id, user.id, "  Hello, world!  ")

      assert message.content == "Hello, world!"
    end

    test "updates sender's last_read_at" do
      %{conversation: conversation, user: user} = conversation_with_participant(last_read_at: nil)

      # Truncate to second since utc_datetime fields don't have microsecond precision.
      before = DateTime.utc_now() |> DateTime.truncate(:second)
      {:ok, _message} = SendMessage.execute(conversation.id, user.id, "Hello!")

      {:ok, participant} = KlassHero.Messaging.get_participant(conversation.id, user.id)
      assert participant.last_read_at != nil
      assert DateTime.compare(participant.last_read_at, before) in [:gt, :eq]
    end

    test "returns not_participant error for non-participant" do
      conversation = insert(:conversation_schema)
      user = AccountsFixtures.user_fixture()

      assert {:error, :not_participant} =
               SendMessage.execute(conversation.id, user.id, "Hello!")
    end

    test "allows system message type" do
      %{conversation: conversation, user: user} = conversation_with_participant()

      assert {:ok, message} =
               SendMessage.execute(
                 conversation.id,
                 user.id,
                 "User joined",
                 message_type: :system
               )

      assert message.message_type == :system
    end

    test "returns error for participant who has left" do
      %{conversation: conversation, user: user} =
        conversation_with_participant(left_at: DateTime.utc_now())

      assert {:error, :not_participant} =
               SendMessage.execute(conversation.id, user.id, "Hello!")
    end

    test "rejects message from parent in broadcast conversation" do
      provider_user = AccountsFixtures.user_fixture()
      provider = insert(:provider_profile_schema, identity_id: provider_user.id)
      program = insert(:program_schema)
      broadcast = insert_broadcast(provider, program)

      # Parent is a participant but should not be able to send.
      parent_user = AccountsFixtures.user_fixture()
      insert(:participant_schema, conversation_id: broadcast.id, user_id: parent_user.id)

      assert {:error, :broadcast_reply_not_allowed} =
               SendMessage.execute(broadcast.id, parent_user.id, "My reply")
    end

    test "allows provider to send in their own broadcast conversation" do
      provider_user = AccountsFixtures.user_fixture()
      provider = insert(:provider_profile_schema, identity_id: provider_user.id)
      program = insert(:program_schema)
      broadcast = insert_broadcast(provider, program)

      insert(:participant_schema, conversation_id: broadcast.id, user_id: provider_user.id)

      assert {:ok, message} =
               SendMessage.execute(broadcast.id, provider_user.id, "Follow-up!")

      assert message.content == "Follow-up!"
    end

    test "allows provider to send in broadcast when pre-fetched conversation is passed" do
      provider_user = AccountsFixtures.user_fixture()
      provider = insert(:provider_profile_schema, identity_id: provider_user.id)
      program = insert(:program_schema)
      broadcast = insert_broadcast(provider, program)

      insert(:participant_schema, conversation_id: broadcast.id, user_id: provider_user.id)

      domain_conversation = broadcast
      assert %Conversation{} = domain_conversation

      assert {:ok, message} =
               SendMessage.execute(broadcast.id, provider_user.id, "Fast path!", conversation: domain_conversation)

      assert message.content == "Fast path!"
    end

    test "rejects mismatched conversation struct — falls back to DB fetch" do
      provider_user = AccountsFixtures.user_fixture()
      provider = insert(:provider_profile_schema, identity_id: provider_user.id)
      program = insert(:program_schema)
      broadcast = insert_broadcast(provider, program)

      parent_user = AccountsFixtures.user_fixture()
      insert(:participant_schema, conversation_id: broadcast.id, user_id: parent_user.id)

      # Build a direct conversation domain struct with a different ID.
      direct = insert(:conversation_schema, type: "direct", provider_id: provider.id)
      mismatched_conversation = direct

      # Trigger: parent passes a direct conversation struct targeting a broadcast conversation_id
      # Why: the ID mismatch must cause a DB fetch, which correctly identifies the broadcast
      # Outcome: parent is still rejected from broadcast
      assert {:error, :broadcast_reply_not_allowed} =
               SendMessage.execute(broadcast.id, parent_user.id, "Sneaky reply", conversation: mismatched_conversation)
    end
  end

  describe "broadcast send permission for staff" do
    test "allows assigned staff to send in broadcast" do
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)
      staff_user = AccountsFixtures.user_fixture()
      broadcast = insert_broadcast(provider, program)

      insert(:staff_member_schema,
        provider_id: provider.id,
        user_id: staff_user.id,
        active: true
      )

      insert(:participant_schema, conversation_id: broadcast.id, user_id: staff_user.id)

      assert {:ok, message} =
               SendMessage.execute(broadcast.id, staff_user.id, "Hello from staff!")

      assert message.content == "Hello from staff!"
    end

    test "rejects user who is not owner and not assigned staff in broadcast" do
      provider_user = AccountsFixtures.user_fixture()
      provider = insert(:provider_profile_schema, identity_id: provider_user.id)
      program = insert(:program_schema, provider_id: provider.id)
      non_staff_user = AccountsFixtures.user_fixture()
      broadcast = insert_broadcast(provider, program)

      insert(:participant_schema, conversation_id: broadcast.id, user_id: non_staff_user.id)

      assert {:error, :broadcast_reply_not_allowed} =
               SendMessage.execute(broadcast.id, non_staff_user.id, "Sneaky reply")
    end

    # #1320: an ended employment leaves the conversation membership standing.
    # Deactivation deliberately keeps the assignment and the participant row
    # (#1237); hard removal destroys the assignment with no event at all (#1292).
    # Either way the participant row survives, so `staff_members` — the row's
    # `active` flag, or its absence — is the only thing that tells these senders
    # apart from staff who may still reply.
    #
    # This used to also seed an `active: true` row in the
    # `program_staff_participants` mirror and pin it as a precondition, because
    # the mirror was never told about either exit and so kept authorizing both.
    # #1321 deleted the mirror; the guard now reads `staff_members` directly, and
    # neither exit is expressible as a stale row any more.
    test "rejects staff whose employment ended" do
      for {label, employed_row?} <- [{"deactivated", true}, {"hard-removed", false}] do
        provider = insert(:provider_profile_schema)
        program = insert(:program_schema, provider_id: provider.id)
        staff_user = AccountsFixtures.user_fixture()
        broadcast = insert_broadcast(provider, program)

        if employed_row? do
          insert(:staff_member_schema,
            provider_id: provider.id,
            user_id: staff_user.id,
            active: false
          )
        end

        insert(:participant_schema, conversation_id: broadcast.id, user_id: staff_user.id)

        assert SendMessage.execute(broadcast.id, staff_user.id, "Still here") ==
                 {:error, :broadcast_reply_not_allowed},
               "expected a #{label} staff member to be denied"
      end
    end

    # Bug #669: a staff_member of the provider should be able to follow up in a
    # broadcast even without a per-program assignment. Employment at the provider
    # is the whole authorization fact — staff may follow up on any program of
    # their provider — so a per-program check would only ever narrow it wrongly.
    test "allows active staff_member of provider to send in broadcast even without program assignment" do
      staff_user = AccountsFixtures.user_fixture()
      provider = insert(:provider_profile_schema)
      program = insert(:program_schema, provider_id: provider.id)

      insert(:staff_member_schema,
        provider_id: provider.id,
        user_id: staff_user.id,
        active: true
      )

      broadcast = insert_broadcast(provider, program)
      insert(:participant_schema, conversation_id: broadcast.id, user_id: staff_user.id)

      # Note: NO program assignment for this staff/program combo, deliberately.

      assert {:ok, message} =
               SendMessage.execute(broadcast.id, staff_user.id, "Hello from provider staff!")

      assert message.content == "Hello from provider staff!"
    end

    # Regression for PR #678 review: a user with active staff_member rows at
    # multiple providers must be authorised for *each* provider's broadcasts —
    # not just the one the scope resolves to. The pre-fix adapter delegated to
    # `Provider.get_active_staff_member_by_user/1`, which returns a single row
    # (today: selection-ordered — last_selected_at, employer-first, newest;
    # #969 switcher) and would wrongly deny posts in the other providers'
    # broadcasts.
    test "allows staff active at multiple providers to send in non-latest provider's broadcast" do
      staff_user = AccountsFixtures.user_fixture()

      # Older active staff_member at provider A.
      provider_a = insert(:provider_profile_schema)
      program_a = insert(:program_schema, provider_id: provider_a.id)

      insert(:staff_member_schema,
        provider_id: provider_a.id,
        user_id: staff_user.id,
        active: true
      )

      # Newer active staff_member at provider B (the scope-resolved row here:
      # no selection and both are employer rows, so newest wins).
      provider_b = insert(:provider_profile_schema)

      insert(:staff_member_schema,
        provider_id: provider_b.id,
        user_id: staff_user.id,
        active: true
      )

      broadcast = insert_broadcast(provider_a, program_a)
      insert(:participant_schema, conversation_id: broadcast.id, user_id: staff_user.id)

      assert {:ok, message} =
               SendMessage.execute(
                 broadcast.id,
                 staff_user.id,
                 "Hello from staff of provider A"
               )

      assert message.content == "Hello from staff of provider A"
    end
  end

  describe "execute/4 with attachments" do
    test "sends message with text and attachments" do
      %{conversation: conversation, user: user} = conversation_with_participant()

      file_data = [
        %{binary: "fake-image-bytes", filename: "photo.jpg", content_type: "image/jpeg", size: 1_000}
      ]

      assert {:ok, message} =
               SendMessage.execute(conversation.id, user.id, "Check this out!", attachments: file_data)

      assert message.content == "Check this out!"
      assert length(message.attachments) == 1
      assert hd(message.attachments).original_filename == "photo.jpg"
    end

    test "sends photo-only message (nil content)" do
      %{conversation: conversation, user: user} = conversation_with_participant()

      file_data = [
        %{binary: "fake-image-bytes", filename: "photo.jpg", content_type: "image/jpeg", size: 1_000}
      ]

      assert {:ok, message} =
               SendMessage.execute(conversation.id, user.id, nil, attachments: file_data)

      assert message.content == nil
      assert length(message.attachments) == 1
    end

    test "rejects empty message — no content and no attachments" do
      %{conversation: conversation, user: user} = conversation_with_participant()

      assert {:error, :empty_message} =
               SendMessage.execute(conversation.id, user.id, nil, attachments: [])
    end

    test "rejects invalid attachment content type" do
      %{conversation: conversation, user: user} = conversation_with_participant()

      file_data = [
        %{binary: "fake-bytes", filename: "doc.pdf", content_type: "application/pdf", size: 1_000}
      ]

      assert {:error, :invalid_attachment_type} =
               SendMessage.execute(conversation.id, user.id, nil, attachments: file_data)
    end

    test "rejects oversized attachment" do
      %{conversation: conversation, user: user} = conversation_with_participant()

      file_data = [
        %{binary: "fake-bytes", filename: "huge.jpg", content_type: "image/jpeg", size: 11_000_000}
      ]

      assert {:error, :attachment_too_large} =
               SendMessage.execute(conversation.id, user.id, nil, attachments: file_data)
    end

    test "rejects more than 5 attachments" do
      %{conversation: conversation, user: user} = conversation_with_participant()

      file_data =
        for i <- 1..6 do
          %{binary: "fake-bytes", filename: "photo#{i}.jpg", content_type: "image/jpeg", size: 1_000}
        end

      assert {:error, :too_many_attachments} =
               SendMessage.execute(conversation.id, user.id, nil, attachments: file_data)
    end

    test "message and attachments are persisted atomically" do
      %{conversation: conversation, user: user} = conversation_with_participant()

      file_data = [
        %{binary: "fake-image-bytes", filename: "photo.jpg", content_type: "image/jpeg", size: 1_000}
      ]

      assert {:ok, message} =
               SendMessage.execute(conversation.id, user.id, "With photo", attachments: file_data)

      assert message.content == "With photo"
      assert length(message.attachments) == 1

      # Attachment is actually in the DB.
      attachments = KlassHero.Messaging.list_attachments_for_message(message.id)
      assert length(attachments) == 1
      assert hd(attachments).original_filename == "photo.jpg"
    end
  end

  # A direct conversation with one enrolled participant (backed by a real user).
  # Extra participant attrs (e.g. last_read_at:, left_at:) override the defaults.
  # #1348: attribution used to be a live staffing lookup at render time, so it
  # rewrote itself whenever employment changed. The role is resolved here, from the
  # same predicate that authorizes the send, and recorded on the row.
  describe "sender_role" do
    test "records :provider for the provider owner" do
      provider_user = AccountsFixtures.user_fixture()
      provider = insert(:provider_profile_schema, identity_id: provider_user.id)
      program = insert(:program_schema, provider_id: provider.id)
      broadcast = insert_broadcast(provider, program)
      insert(:participant_schema, conversation_id: broadcast.id, user_id: provider_user.id)

      assert {:ok, message} = SendMessage.execute(broadcast.id, provider_user.id, "Announcement")
      assert message.sender_role == :provider
    end

    test "records :staff for a staff member assigned to the program" do
      %{provider: provider, program: program, staff_user: staff_user, staff: staff, broadcast: broadcast} =
        broadcast_with_staff()

      insert(:program_staff_assignment_schema,
        provider_id: provider.id,
        program_id: program.id,
        staff_member_id: staff.id
      )

      assert {:ok, message} = SendMessage.execute(broadcast.id, staff_user.id, "From staff")
      assert message.sender_role == :staff
    end

    # The defect the issue did not name: send authorization is provider-wide
    # (#669), but rendering used a program-scoped set, so an active staff member
    # with no assignment to *this* program rendered parent-side immediately — no
    # departure required. Resolving the role from the authorization predicate is
    # what makes the two agree.
    test "records :staff for active staff with no assignment to this program" do
      %{staff_user: staff_user, broadcast: broadcast} = broadcast_with_staff()

      assert {:ok, message} = SendMessage.execute(broadcast.id, staff_user.id, "From staff")
      assert message.sender_role == :staff
    end

    test "records :parent for a participant who is neither owner nor staff" do
      %{conversation: conversation, user: user} = conversation_with_participant()

      assert {:ok, message} = SendMessage.execute(conversation.id, user.id, "From a parent")
      assert message.sender_role == :parent
    end

    test "the recorded role survives the sender's deactivation" do
      %{staff_user: staff_user, staff: staff, broadcast: broadcast} = broadcast_with_staff()

      assert {:ok, message} = SendMessage.execute(broadcast.id, staff_user.id, "While employed")
      assert {:ok, _} = Provider.deactivate_staff_member(staff)

      assert KlassHero.Repo.get!(Message, message.id).sender_role == :staff
    end
  end

  defp broadcast_with_staff do
    provider = insert(:provider_profile_schema)
    program = insert(:program_schema, provider_id: provider.id)
    staff_user = AccountsFixtures.user_fixture()
    staff = insert(:staff_member_schema, provider_id: provider.id, user_id: staff_user.id, active: true)
    broadcast = insert_broadcast(provider, program)
    insert(:participant_schema, conversation_id: broadcast.id, user_id: staff_user.id)

    %{provider: provider, program: program, staff_user: staff_user, staff: staff, broadcast: broadcast}
  end

  defp conversation_with_participant(participant_attrs \\ []) do
    conversation = insert(:conversation_schema)
    user = AccountsFixtures.user_fixture()

    insert(
      :participant_schema,
      Keyword.merge([conversation_id: conversation.id, user_id: user.id], participant_attrs)
    )

    %{conversation: conversation, user: user}
  end

  defp insert_broadcast(provider, program) do
    insert(:conversation_schema,
      type: "program_broadcast",
      provider_id: provider.id,
      program_id: program.id,
      subject: "Announcement"
    )
  end
end
