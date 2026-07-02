defmodule KlassHero.Messaging.InboundEmailTest do
  @moduledoc """
  Covers the flattened InboundEmail schema-as-struct: its changesets (the sole
  validation gatekeeper), the Ecto.Enum status/content_status fields, and
  persistence through the public `KlassHero.Messaging` API — including the
  idempotent mark-as-read path and status/content updates.
  """

  use KlassHero.DataCase, async: true

  alias KlassHero.AccountsFixtures
  alias KlassHero.Messaging
  alias KlassHero.Messaging.InboundEmail
  alias KlassHero.MessagingFixtures

  describe "create_changeset/2" do
    test "valid with the required fields" do
      changeset = InboundEmail.create_changeset(MessagingFixtures.valid_inbound_email_attrs())

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :status) == :unread
      assert Ecto.Changeset.get_field(changeset, :content_status) == :fetched
    end

    test "requires resend_id, from_address, subject, received_at" do
      changeset = InboundEmail.create_changeset(%{})

      errors = errors_on(changeset)
      assert errors[:resend_id] == ["can't be blank"]
      assert errors[:from_address] == ["can't be blank"]
      assert errors[:subject] == ["can't be blank"]
      assert errors[:received_at] == ["can't be blank"]
    end

    test "rejects a status outside the enum" do
      attrs = MessagingFixtures.valid_inbound_email_attrs(%{status: :spam})
      changeset = InboundEmail.create_changeset(attrs)

      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "rejects a content_status outside the enum" do
      attrs = MessagingFixtures.valid_inbound_email_attrs(%{content_status: :queued})
      changeset = InboundEmail.create_changeset(attrs)

      assert %{content_status: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "create_inbound_email/1 and lookups" do
    test "persists with enums loaded as atoms and looks up by id + resend_id" do
      attrs = MessagingFixtures.valid_inbound_email_attrs()

      assert {:ok, %InboundEmail{} = email} = Messaging.create_inbound_email(attrs)
      assert email.status == :unread
      assert {:ok, ^email} = Messaging.get_inbound_email_by_id(email.id)
      assert {:ok, by_resend} = Messaging.get_inbound_email_by_resend_id(email.resend_id)
      assert by_resend.id == email.id
    end

    test "enforces the unique resend_id constraint" do
      attrs = MessagingFixtures.valid_inbound_email_attrs()
      {:ok, _} = Messaging.create_inbound_email(attrs)

      assert {:error, changeset} = Messaging.create_inbound_email(attrs)
      assert %{resend_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "get_inbound_email_by_id returns :not_found for unknown id" do
      assert {:error, :not_found} = Messaging.get_inbound_email_by_id(Ecto.UUID.generate())
    end
  end

  describe "list_inbound_emails/1 and count_inbound_emails_by_status/1" do
    test "lists newest first with has_more and filters by status" do
      _a = MessagingFixtures.inbound_email_fixture()
      b = MessagingFixtures.inbound_email_fixture()

      {:ok, _} = Messaging.update_inbound_email_status(b.id, "archived")

      assert {:ok, emails, true} = Messaging.list_inbound_emails(limit: 1)
      assert length(emails) == 1

      assert {:ok, [only], false} = Messaging.list_inbound_emails(status: :archived)
      assert only.id == b.id
      assert Messaging.count_inbound_emails_by_status(:archived) == 1
      assert Messaging.count_inbound_emails_by_status(:unread) == 1
    end
  end

  describe "update_inbound_email_content/2 and update_inbound_email_status/3" do
    test "fills content and flips content_status" do
      email = MessagingFixtures.inbound_email_fixture(%{content_status: "pending"})

      assert {:ok, updated} =
               Messaging.update_inbound_email_content(email.id, %{
                 body_html: "<p>Body</p>",
                 content_status: "fetched"
               })

      assert updated.content_status == :fetched
      assert updated.body_html == "<p>Body</p>"
    end

    test "returns :not_found for an unknown id" do
      assert {:error, :not_found} =
               Messaging.update_inbound_email_status(Ecto.UUID.generate(), "archived")
    end
  end

  describe "mark_inbound_email_read/2" do
    test "marks an unread email as read, then is idempotent" do
      user = AccountsFixtures.user_fixture()
      email = MessagingFixtures.inbound_email_fixture()
      assert email.status == :unread

      assert {:ok, read} = Messaging.mark_inbound_email_read(email, user.id)
      assert read.status == :read
      assert read.read_by_id == user.id
      assert read.read_at != nil

      # Second mark by another reader is a no-op — original reader/timestamp preserved.
      other = AccountsFixtures.user_fixture()
      assert {:ok, again} = Messaging.mark_inbound_email_read(read, other.id)
      assert again.read_by_id == user.id
      assert DateTime.compare(again.read_at, read.read_at) == :eq
    end
  end
end
