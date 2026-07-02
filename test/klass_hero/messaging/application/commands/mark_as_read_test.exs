defmodule KlassHero.Messaging.Application.Commands.MarkAsReadTest do
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.AccountsFixtures
  alias KlassHero.Messaging.Application.Commands.MarkAsRead
  alias KlassHero.Messaging.Participant

  describe "execute/3" do
    test "updates last_read_at timestamp" do
      conversation = insert(:conversation_schema)
      user = AccountsFixtures.user_fixture()

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id,
        last_read_at: nil
      )

      assert {:ok, participant} = MarkAsRead.execute(conversation.id, user.id)
      assert %Participant{} = participant
      assert participant.last_read_at != nil
    end

    test "uses provided timestamp" do
      conversation = insert(:conversation_schema)
      user = AccountsFixtures.user_fixture()

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      read_at = ~U[2025-01-15 12:00:00Z]

      assert {:ok, participant} = MarkAsRead.execute(conversation.id, user.id, read_at)
      assert participant.last_read_at == read_at
    end

    test "uses current time when timestamp not provided" do
      conversation = insert(:conversation_schema)
      user = AccountsFixtures.user_fixture()

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id
      )

      # Truncate to second since utc_datetime fields don't have microsecond precision
      before = DateTime.utc_now() |> DateTime.truncate(:second)
      {:ok, participant} = MarkAsRead.execute(conversation.id, user.id)
      after_time = DateTime.utc_now() |> DateTime.truncate(:second)

      assert DateTime.compare(participant.last_read_at, before) in [:gt, :eq]
      assert DateTime.compare(participant.last_read_at, after_time) in [:lt, :eq]
    end

    test "returns not_participant error when user is not participant" do
      conversation = insert(:conversation_schema)
      user = AccountsFixtures.user_fixture()

      assert {:error, :not_participant} = MarkAsRead.execute(conversation.id, user.id)
    end

    test "updates even when last_read_at was already set" do
      conversation = insert(:conversation_schema)
      user = AccountsFixtures.user_fixture()

      old_read_at = ~U[2025-01-10 12:00:00Z]

      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id,
        last_read_at: old_read_at
      )

      new_read_at = ~U[2025-01-15 12:00:00Z]

      assert {:ok, participant} = MarkAsRead.execute(conversation.id, user.id, new_read_at)
      assert participant.last_read_at == new_read_at
    end
  end
end
