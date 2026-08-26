defmodule KlassHero.Release.BackfillDirectConversationPrincipalsTest do
  use KlassHero.DataCase, async: true

  import KlassHero.AccountsFixtures
  import KlassHero.Factory

  alias KlassHero.Release.BackfillDirectConversationPrincipals
  alias KlassHero.Release.BackfillDirectConversationPrincipals.UnresolvedError

  # Not the :participant_schema factory: its default `conversation` is built
  # eagerly even when overridden, so every seat would leave an orphan :direct
  # conversation behind and the backfill would rightly refuse to resolve it.
  defp seat(conversation_id, user_id) do
    {:ok, _} = KlassHero.Messaging.add_participant(%{conversation_id: conversation_id, user_id: user_id})
  end

  # A schemaless query hands back raw 16-byte uuids; cast so failures read as ids.
  defp principals(conversation_id) do
    {a, b} =
      Repo.one!(
        from(c in "conversations",
          where: c.id == type(^conversation_id, :binary_id),
          select: {c.principal_a_id, c.principal_b_id}
        )
      )

    {Ecto.UUID.cast!(a), Ecto.UUID.cast!(b)}
  end

  # Owner + parent + a staff member seated by AddAssignedStaff — the shape the
  # backfill exists for. Staff are participants, never principals.
  defp thread_with_seated_staff do
    owner = user_fixture()
    parent = user_fixture()
    staff = user_fixture()

    provider = insert(:provider_profile_schema, identity_id: owner.id)
    insert(:parent_profile_schema, identity_id: parent.id)
    insert(:staff_member_schema, provider_id: provider.id, user_id: staff.id)

    conversation = insert(:conversation_schema, type: :direct, provider_id: provider.id)

    for user <- [owner, parent, staff], do: seat(conversation.id, user.id)

    %{conversation: conversation, owner: owner, parent: parent, staff: staff}
  end

  test "fills the owner/parent pair and leaves seated staff out of it" do
    %{conversation: conversation, owner: owner, parent: parent, staff: staff} =
      thread_with_seated_staff()

    assert {:ok, %{rows_filled: 1}} = BackfillDirectConversationPrincipals.run(Repo)

    {a, b} = principals(conversation.id)

    assert Enum.sort([a, b]) == Enum.sort([owner.id, parent.id])
    refute staff.id in [a, b]
  end

  test "stores the pair ordered, so an unordered lookup is one equality check" do
    %{conversation: conversation} = thread_with_seated_staff()

    assert {:ok, _} = BackfillDirectConversationPrincipals.run(Repo)

    {a, b} = principals(conversation.id)
    assert a < b
  end

  test "is idempotent — a second run fills nothing" do
    thread_with_seated_staff()

    assert {:ok, %{rows_filled: 1}} = BackfillDirectConversationPrincipals.run(Repo)
    assert {:ok, %{rows_filled: 0}} = BackfillDirectConversationPrincipals.run(Repo)
  end

  # The row is not guessed at: production was verified clean before this shipped,
  # so an unresolvable row means something unexpected exists and must be looked at.
  test "raises rather than guessing when no parent participates" do
    owner = user_fixture()
    colleague = user_fixture()
    provider = insert(:provider_profile_schema, identity_id: owner.id)
    conversation = insert(:conversation_schema, type: :direct, provider_id: provider.id)

    for user <- [owner, colleague], do: seat(conversation.id, user.id)

    assert_raise UnresolvedError, fn -> BackfillDirectConversationPrincipals.run(Repo) end
  end
end
