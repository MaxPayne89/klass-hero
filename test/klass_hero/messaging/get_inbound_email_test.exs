defmodule KlassHero.Messaging.GetInboundEmailTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.AccountsFixtures
  alias KlassHero.Messaging.GetInboundEmail
  alias KlassHero.Messaging.InboundEmail
  alias KlassHero.MessagingFixtures

  describe "execute/2" do
    test "fetches an email by id" do
      email = MessagingFixtures.inbound_email_fixture()

      assert {:ok, %InboundEmail{} = fetched} = GetInboundEmail.execute(email.id)
      assert fetched.id == email.id
      assert fetched.resend_id == email.resend_id
    end

    test "returns {:error, :not_found} for unknown id" do
      assert {:error, :not_found} = GetInboundEmail.execute(Ecto.UUID.generate())
    end

    test "marks unread email as read when mark_read: true and reader_id provided" do
      user = AccountsFixtures.user_fixture()
      email = MessagingFixtures.inbound_email_fixture()

      assert email.status == :unread

      assert {:ok, %InboundEmail{} = updated} =
               GetInboundEmail.execute(email.id, mark_read: true, reader_id: user.id)

      assert updated.status == :read
      assert updated.read_by_id == user.id
      assert %DateTime{} = updated.read_at
    end

    test "does not mark as read when mark_read is false" do
      user = AccountsFixtures.user_fixture()
      email = MessagingFixtures.inbound_email_fixture()

      assert {:ok, fetched} =
               GetInboundEmail.execute(email.id, mark_read: false, reader_id: user.id)

      assert fetched.status == :unread
    end

    test "does not mark as read when reader_id is missing" do
      email = MessagingFixtures.inbound_email_fixture()

      assert {:ok, fetched} = GetInboundEmail.execute(email.id, mark_read: true)
      assert fetched.status == :unread
    end

    test "does not re-mark an already-read email" do
      user = AccountsFixtures.user_fixture()
      email = MessagingFixtures.inbound_email_fixture()

      # First read — stores read_at
      {:ok, first_read} = GetInboundEmail.execute(email.id, mark_read: true, reader_id: user.id)
      assert first_read.status == :read
      original_read_at = first_read.read_at

      another_user = AccountsFixtures.user_fixture()

      # Second read by another user — should return unchanged email
      {:ok, second_read} =
        GetInboundEmail.execute(email.id, mark_read: true, reader_id: another_user.id)

      # Trigger: email is already :read
      # Why: idempotent — preserve original reader_id and read_at
      # Outcome: read_at and read_by_id unchanged from first read
      assert second_read.read_by_id == user.id
      assert DateTime.compare(second_read.read_at, original_read_at) == :eq
    end

    test "does not mark archived email as read" do
      user = AccountsFixtures.user_fixture()
      email = MessagingFixtures.inbound_email_fixture(%{status: "archived"})

      assert {:ok, fetched} =
               GetInboundEmail.execute(email.id, mark_read: true, reader_id: user.id)

      assert fetched.status == :archived
    end
  end
end
