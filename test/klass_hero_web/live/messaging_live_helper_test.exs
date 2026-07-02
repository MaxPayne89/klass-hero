defmodule KlassHeroWeb.MessagingLiveHelperTest do
  use ExUnit.Case, async: true

  alias KlassHero.Messaging.Message
  alias KlassHeroWeb.MessagingLiveHelper

  describe "get_conversation_title/3" do
    test "returns parent name with child names for direct conversation with enrolled children" do
      conversation = %{type: :direct}
      child_names = ["Emma", "Liam"]
      other_name = "Sarah Johnson"

      assert MessagingLiveHelper.get_conversation_title(conversation, child_names, other_name) ==
               "Sarah Johnson for Emma, Liam"
    end

    test "returns parent name with single child for direct conversation" do
      conversation = %{type: :direct}

      assert MessagingLiveHelper.get_conversation_title(conversation, ["Emma"], "Sarah Johnson") ==
               "Sarah Johnson for Emma"
    end

    test "returns other participant name when no enrolled children" do
      conversation = %{type: :direct}

      assert MessagingLiveHelper.get_conversation_title(conversation, [], "Sarah Johnson") ==
               "Sarah Johnson"
    end

    test "returns subject for program_broadcast with subject" do
      conversation = %{type: :program_broadcast, subject: "Summer Camp Update"}

      assert MessagingLiveHelper.get_conversation_title(conversation, [], nil) ==
               "Summer Camp Update"
    end

    test "returns 'Program Broadcast' for broadcast without subject" do
      conversation = %{type: :program_broadcast, subject: nil}

      assert MessagingLiveHelper.get_conversation_title(conversation, [], nil) ==
               "Program Broadcast"
    end

    test "returns 'Conversation' as fallback" do
      assert MessagingLiveHelper.get_conversation_title(%{type: :direct}, [], nil) ==
               "Conversation"
    end
  end

  describe "enrolled_child_names_for/2" do
    test "returns [] for :parent variant (suffix is suppressed in title)" do
      assert MessagingLiveHelper.enrolled_child_names_for(:parent, ["Emma", "Liam"]) == []
      assert MessagingLiveHelper.enrolled_child_names_for(:parent, []) == []
    end

    test "passes the names through unchanged for :provider variant" do
      assert MessagingLiveHelper.enrolled_child_names_for(:provider, ["Emma", "Liam"]) ==
               ["Emma", "Liam"]

      assert MessagingLiveHelper.enrolled_child_names_for(:provider, []) == []
    end

    test "passes the names through unchanged for :staff variant" do
      assert MessagingLiveHelper.enrolled_child_names_for(:staff, ["Emma"]) == ["Emma"]
    end
  end

  describe "own_message?/2" do
    test "returns true when the message sender is the given user" do
      user_id = Ecto.UUID.generate()

      message = %Message{
        id: Ecto.UUID.generate(),
        conversation_id: Ecto.UUID.generate(),
        sender_id: user_id,
        content: "hello"
      }

      assert MessagingLiveHelper.own_message?(message, user_id) == true
    end

    test "returns false when the message sender is a different user" do
      message = %Message{
        id: Ecto.UUID.generate(),
        conversation_id: Ecto.UUID.generate(),
        sender_id: Ecto.UUID.generate(),
        content: "hello"
      }

      assert MessagingLiveHelper.own_message?(message, Ecto.UUID.generate()) == false
    end
  end

  describe "get_sender_name/2" do
    test "returns the name when sender_id is present in the map" do
      id_1 = Ecto.UUID.generate()
      id_2 = Ecto.UUID.generate()
      sender_names = %{id_1 => "Alice", id_2 => "Bob"}

      assert MessagingLiveHelper.get_sender_name(sender_names, id_1) == "Alice"
      assert MessagingLiveHelper.get_sender_name(sender_names, id_2) == "Bob"
    end

    test "returns 'Unknown' as fallback when sender_id is not in the map" do
      missing_id = Ecto.UUID.generate()

      assert MessagingLiveHelper.get_sender_name(%{}, missing_id) == "Unknown"

      assert MessagingLiveHelper.get_sender_name(%{Ecto.UUID.generate() => "Name"}, missing_id) ==
               "Unknown"
    end
  end
end
