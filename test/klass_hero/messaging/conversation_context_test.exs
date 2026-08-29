defmodule KlassHero.Messaging.ConversationContextTest do
  @moduledoc """
  Replaces the `get_conversation_summary_context/2` block that seeded
  `conversation_summaries` rows and asserted them back — a test of the fixture, not the
  derivation. These build real conversations, participants and enrollments and let the
  derivation do the work.

  Exercised through `Messaging.get_conversation_context/2` rather than the module
  directly: that is the entry point the thread page uses, and it covers the load as
  well as the derivation.
  """

  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.AccountsFixtures
  alias KlassHero.Messaging
  alias KlassHero.Messaging.ConversationContext

  describe "get_conversation_context/2" do
    test "names the other principal and the children the thread is about" do
      %{parent_user: parent_user, provider_user: provider_user, conversation: conversation} =
        direct_thread_about_a_child("Emma")

      assert %{other_participant_name: name, enrolled_child_names: ["Emma"]} =
               Messaging.get_conversation_context(conversation.id, provider_user.id)

      assert name == display_name(parent_user)

      # Symmetric: each side is told who the *other* one is.
      assert %{other_participant_name: other} =
               Messaging.get_conversation_context(conversation.id, parent_user.id)

      assert other == display_name(provider_user)
    end

    test "lists every enrolled child of the thread, sorted" do
      %{provider_user: provider_user, conversation: conversation, parent: parent, program: program} =
        direct_thread_about_a_child("Zoe")

      enroll_child(parent, program, "Alice")

      assert %{enrolled_child_names: ["Alice", "Zoe"]} =
               Messaging.get_conversation_context(conversation.id, provider_user.id)
    end

    test "a thread with no program has no children to name" do
      provider = insert(:provider_profile_schema)
      provider_user = AccountsFixtures.user_fixture()
      parent_user = AccountsFixtures.user_fixture()

      conversation = direct_conversation(provider, provider_user, parent_user, nil)

      assert %{enrolled_child_names: [], other_participant_name: name} =
               Messaging.get_conversation_context(conversation.id, provider_user.id)

      assert name == display_name(parent_user)
    end

    test "a broadcast has neither — it is titled by its subject" do
      provider = insert(:provider_profile_schema)
      provider_user = AccountsFixtures.user_fixture()

      conversation =
        insert(:conversation_schema,
          type: :program_broadcast,
          provider_id: provider.id,
          subject: "Trip on Friday"
        )

      insert(:participant_schema, conversation_id: conversation.id, user_id: provider_user.id)

      assert %{enrolled_child_names: [], other_participant_name: nil} =
               Messaging.get_conversation_context(conversation.id, provider_user.id)
    end

    # The rule `staff_conversations_live.ex` documents: a provider owner looking at a
    # staff member's thread is neither a principal nor seated in it, so the thread
    # titles generically. #1523 is the request to change this.
    test "a viewer who is neither principal nor participant gets nothing" do
      %{conversation: conversation} = direct_thread_about_a_child("Emma")
      outsider = AccountsFixtures.user_fixture()

      assert %{enrolled_child_names: [], other_participant_name: nil} =
               Messaging.get_conversation_context(conversation.id, outsider.id)
    end

    test "an unknown conversation is empty rather than an error" do
      assert %{enrolled_child_names: [], other_participant_name: nil} =
               Messaging.get_conversation_context(Ecto.UUID.generate(), Ecto.UUID.generate())
    end
  end

  # Threads predating the principal pair (#747) carry neither principal. The only
  # answer left is the other active participant, which is why the fallback exists.
  describe "pre-#747 threads with no principals" do
    test "falls back to the other active participant" do
      provider = insert(:provider_profile_schema)
      provider_user = AccountsFixtures.user_fixture()
      parent_user = AccountsFixtures.user_fixture()

      conversation =
        insert(:conversation_schema,
          type: :direct,
          provider_id: provider.id,
          principal_a_id: nil,
          principal_b_id: nil
        )

      insert(:participant_schema, conversation_id: conversation.id, user_id: provider_user.id)
      insert(:participant_schema, conversation_id: conversation.id, user_id: parent_user.id)

      assert %{other_participant_name: name} =
               Messaging.get_conversation_context(conversation.id, provider_user.id)

      assert name == display_name(parent_user)
    end
  end

  describe "for_conversations/2" do
    test "returns an entry for every conversation, so callers may fetch! safely" do
      assert ConversationContext.for_conversations([], Ecto.UUID.generate()) == %{}

      %{conversation: conversation, provider_user: provider_user} =
        direct_thread_about_a_child("Emma")

      {:ok, loaded} = Messaging.get_conversation_by_id(conversation.id, preload: [:participants])

      by_id = ConversationContext.for_conversations([loaded], provider_user.id)

      assert %{other_participant_name: _} = Map.fetch!(by_id, conversation.id)
    end
  end

  defp direct_thread_about_a_child(child_name) do
    provider = insert(:provider_profile_schema)
    provider_user = AccountsFixtures.user_fixture()
    parent_user = AccountsFixtures.user_fixture()
    program = insert(:program_schema, provider_id: provider.id)
    parent = insert(:parent_profile_schema, identity_id: parent_user.id)

    enroll_child(parent, program, child_name)

    conversation = direct_conversation(provider, provider_user, parent_user, program.id)

    %{
      provider: provider,
      provider_user: provider_user,
      parent_user: parent_user,
      parent: parent,
      program: program,
      conversation: conversation
    }
  end

  # `fetch_child_names/2` joins enrollments → children → parents, and matches the parent
  # by `identity_id`, so the enrollment must carry the parent *profile*, not the user.
  defp enroll_child(parent, program, child_name) do
    {child, ^parent} = insert_child_with_guardian(parent: parent, first_name: child_name)

    insert(:enrollment_schema,
      child_id: child.id,
      parent_id: parent.id,
      program_id: program.id,
      status: :confirmed
    )
  end

  # `conversations_principals_ordered` makes the pair canonical, so a direct thread has
  # exactly one representation. Sorting is not cosmetic — an unsorted pair raises.
  defp direct_conversation(provider, user_a, user_b, program_id) do
    [principal_a, principal_b] = Enum.sort([user_a.id, user_b.id])

    conversation =
      insert(:conversation_schema,
        type: :direct,
        provider_id: provider.id,
        program_id: program_id,
        principal_a_id: principal_a,
        principal_b_id: principal_b
      )

    insert(:participant_schema, conversation_id: conversation.id, user_id: user_a.id)
    insert(:participant_schema, conversation_id: conversation.id, user_id: user_b.id)

    conversation
  end

  defp display_name(user) do
    Map.fetch!(KlassHero.Accounts.get_display_names([user.id]), user.id)
  end
end
