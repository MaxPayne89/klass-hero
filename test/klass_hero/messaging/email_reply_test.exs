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

  describe "status_changeset/2 transition guard" do
    # `:sent` is absorbing. Compensation marking a reply failed can be replayed — by the
    # sweep over discarded jobs, or by a Lifeline duplicate racing the original — and
    # without this guard the replay records a delivered reply as failed.
    @transitions [
      {:sending, :sent, true},
      {:sending, :failed, true},
      {:failed, :sent, true},
      {:failed, :failed, true},
      {:sent, :sent, true},
      {:sent, :failed, false}
    ]

    for {from, to, valid?} <- @transitions do
      test "#{from} -> #{to} is #{if valid?, do: "allowed", else: "rejected"}" do
        changeset =
          EmailReply.status_changeset(%EmailReply{status: unquote(from)}, %{status: unquote(to)})

        assert changeset.valid? == unquote(valid?),
               "expected #{unquote(from)} -> #{unquote(to)} to be " <>
                 "#{if unquote(valid?), do: "allowed", else: "rejected"}"
      end
    end

    test "names the rejected transition in the error" do
      changeset = EmailReply.status_changeset(%EmailReply{status: :sent}, %{status: :failed})

      assert %{status: ["cannot transition from sent to failed"]} = errors_on(changeset)
    end

    # The delivery path writes resend_message_id/sent_at alongside the status, so the
    # guard must not reject a changeset merely for carrying more than :status.
    test "allows delivery metadata through on a permitted transition" do
      now = DateTime.utc_now()

      changeset =
        EmailReply.status_changeset(%EmailReply{status: :sending}, %{
          status: :sent,
          resend_message_id: "resend_abc",
          sent_at: now
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :resend_message_id) == "resend_abc"
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

    # Oldest-first, with id as the tiebreak — asserted as an invariant rather than a
    # fixed list, because two replies created in one test can share a timestamp.
    test "returns replies oldest first" do
      email = MessagingFixtures.inbound_email_fixture()
      user = AccountsFixtures.user_fixture()

      for body <- ~w(1 2 3) do
        {:ok, _} =
          Messaging.create_email_reply(%{inbound_email_id: email.id, body: body, sent_by_id: user.id})
      end

      assert {:ok, replies} = Messaging.list_email_replies(email.id)
      assert length(replies) == 3
      assert replies == Enum.sort_by(replies, &{&1.inserted_at, &1.id})
    end

    test "does not return replies belonging to another email" do
      mine = MessagingFixtures.inbound_email_fixture()
      theirs = MessagingFixtures.inbound_email_fixture()
      user = AccountsFixtures.user_fixture()

      {:ok, _} =
        Messaging.create_email_reply(%{inbound_email_id: theirs.id, body: "x", sent_by_id: user.id})

      assert {:ok, []} = Messaging.list_email_replies(mine.id)
    end
  end
end
