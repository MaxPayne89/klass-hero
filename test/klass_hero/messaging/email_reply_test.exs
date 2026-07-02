defmodule KlassHero.Messaging.EmailReplyTest do
  @moduledoc """
  Covers the flattened EmailReply schema-as-struct: its changesets (the sole
  validation gatekeeper), the Ecto.Enum status field, and persistence through
  the public `KlassHero.Messaging` API — create, status transitions, listing.
  """

  use KlassHero.DataCase, async: true

  alias KlassHero.AccountsFixtures
  alias KlassHero.Messaging
  alias KlassHero.Messaging.EmailReply
  alias KlassHero.MessagingFixtures

  describe "create_changeset/2" do
    test "valid with the required fields, defaulting to :sending" do
      attrs = MessagingFixtures.valid_email_reply_attrs()
      changeset = EmailReply.create_changeset(attrs)

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :status) == :sending
    end

    test "requires inbound_email_id, body, sent_by_id" do
      changeset = EmailReply.create_changeset(%{})

      errors = errors_on(changeset)
      assert errors[:inbound_email_id] == ["can't be blank"]
      assert errors[:body] == ["can't be blank"]
      assert errors[:sent_by_id] == ["can't be blank"]
    end

    test "rejects a status outside the enum" do
      attrs = MessagingFixtures.valid_email_reply_attrs(%{status: :queued})
      changeset = EmailReply.create_changeset(attrs)

      assert %{status: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "create_email_reply/1 and status transitions" do
    setup do
      email = MessagingFixtures.inbound_email_fixture()
      user = AccountsFixtures.user_fixture()
      %{email: email, user: user}
    end

    test "persists a reply and transitions it to :sent", %{email: email, user: user} do
      assert {:ok, %EmailReply{} = reply} =
               Messaging.create_email_reply(%{
                 inbound_email_id: email.id,
                 body: "Thanks!",
                 sent_by_id: user.id
               })

      assert reply.status == :sending

      assert {:ok, sent} =
               Messaging.update_email_reply_status(reply.id, "sent", %{
                 resend_message_id: "resend_abc",
                 sent_at: DateTime.utc_now()
               })

      assert sent.status == :sent
      assert sent.resend_message_id == "resend_abc"
    end

    test "enforces the inbound_email_id foreign key", %{user: user} do
      assert {:error, changeset} =
               Messaging.create_email_reply(%{
                 inbound_email_id: Ecto.UUID.generate(),
                 body: "Hi",
                 sent_by_id: user.id
               })

      assert %{inbound_email_id: ["does not exist"]} = errors_on(changeset)
    end

    test "update_email_reply_status returns :not_found for unknown id" do
      assert {:error, :not_found} =
               Messaging.update_email_reply_status(Ecto.UUID.generate(), "failed")
    end
  end

  describe "list_email_replies/1" do
    test "returns every reply for the email" do
      email = MessagingFixtures.inbound_email_fixture()
      user = AccountsFixtures.user_fixture()

      {:ok, first} =
        Messaging.create_email_reply(%{inbound_email_id: email.id, body: "1", sent_by_id: user.id})

      {:ok, second} =
        Messaging.create_email_reply(%{inbound_email_id: email.id, body: "2", sent_by_id: user.id})

      assert {:ok, replies} = Messaging.list_email_replies(email.id)
      assert Enum.map(replies, & &1.id) |> Enum.sort() == Enum.sort([first.id, second.id])
    end
  end
end
