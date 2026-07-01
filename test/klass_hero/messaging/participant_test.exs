defmodule KlassHero.Messaging.ParticipantTest do
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias KlassHero.Messaging.Participant

  describe "create_changeset/2" do
    test "is valid with required attributes" do
      changeset = Participant.create_changeset(%Participant{}, valid_attrs())
      assert changeset.valid?
    end

    test "requires conversation_id, user_id and joined_at" do
      changeset = Participant.create_changeset(%Participant{}, %{})

      assert %{
               conversation_id: ["can't be blank"],
               user_id: ["can't be blank"],
               joined_at: ["can't be blank"]
             } = errors_on(changeset)
    end
  end

  describe "mark_read_changeset/2" do
    test "requires last_read_at" do
      changeset = Participant.mark_read_changeset(%Participant{}, %{})
      assert %{last_read_at: ["can't be blank"]} = errors_on(changeset)
    end

    test "casts last_read_at" do
      read_at = ~U[2025-01-15 12:00:00Z]
      changeset = Participant.mark_read_changeset(%Participant{}, %{last_read_at: read_at})
      assert changeset.valid?
      assert Changeset.get_change(changeset, :last_read_at) == read_at
    end
  end

  describe "leave_changeset/2" do
    test "requires left_at" do
      changeset = Participant.leave_changeset(%Participant{}, %{})
      assert %{left_at: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "active?/1 and left?/1" do
    test "active when left_at is nil, left otherwise" do
      participant = build_participant()
      assert Participant.active?(participant)
      refute Participant.left?(participant)

      left = %{participant | left_at: DateTime.utc_now()}
      refute Participant.active?(left)
      assert Participant.left?(left)
    end
  end

  describe "has_unread?/2" do
    test "false when last_read_at is nil and no messages" do
      refute Participant.has_unread?(build_participant(), nil)
    end

    test "true when last_read_at is nil but messages exist" do
      assert Participant.has_unread?(build_participant(), ~U[2025-01-15 12:00:00Z])
    end

    test "true when latest message is after last_read_at" do
      participant = %{build_participant() | last_read_at: ~U[2025-01-15 10:00:00Z]}
      assert Participant.has_unread?(participant, ~U[2025-01-15 12:00:00Z])
    end

    test "false when latest message is before or equal to last_read_at" do
      participant = %{build_participant() | last_read_at: ~U[2025-01-15 14:00:00Z]}
      refute Participant.has_unread?(participant, ~U[2025-01-15 12:00:00Z])

      at = ~U[2025-01-15 12:00:00Z]
      refute Participant.has_unread?(%{participant | last_read_at: at}, at)
    end

    test "false when last_read_at is set but no messages" do
      participant = %{build_participant() | last_read_at: ~U[2025-01-15 12:00:00Z]}
      refute Participant.has_unread?(participant, nil)
    end
  end

  defp build_participant do
    %Participant{
      id: Ecto.UUID.generate(),
      conversation_id: Ecto.UUID.generate(),
      user_id: Ecto.UUID.generate(),
      joined_at: DateTime.utc_now()
    }
  end

  defp valid_attrs do
    %{
      conversation_id: Ecto.UUID.generate(),
      user_id: Ecto.UUID.generate(),
      joined_at: DateTime.utc_now()
    }
  end

  defp errors_on(changeset) do
    Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
