defmodule KlassHero.Messaging.Adapters.Driving.Workers.SendEmailReplyWorkerTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.Messaging
  alias KlassHero.Messaging.Adapters.Driving.Workers.SendEmailReplyWorker
  alias KlassHero.MessagingFixtures
  alias KlassHero.Test.StubMailerAdapter

  describe "perform/1" do
    test "delivers reply and updates status to sent" do
      email =
        MessagingFixtures.inbound_email_fixture(%{
          message_id: "<original@example.com>"
        })

      reply = MessagingFixtures.email_reply_fixture(%{inbound_email_id: email.id})

      assert :ok =
               SendEmailReplyWorker.perform(%Oban.Job{
                 args: %{"reply_id" => reply.id}
               })

      {:ok, updated} = Messaging.get_email_reply_by_id(reply.id)
      assert updated.status == :sent
      assert updated.sent_at != nil
    end

    # Until StubMailerAdapter existed there was no way to fail a delivery, so this test
    # asserted the happy path under a failure name and could never have gone red.
    test "leaves the reply sending while retries remain" do
      email = MessagingFixtures.inbound_email_fixture()
      reply = MessagingFixtures.email_reply_fixture(%{inbound_email_id: email.id})
      StubMailerAdapter.fail_with({:network, :timeout})

      assert {:error, _reason} =
               SendEmailReplyWorker.perform(%Oban.Job{
                 args: %{"reply_id" => reply.id},
                 attempt: 1,
                 max_attempts: 3
               })

      {:ok, updated} = Messaging.get_email_reply_by_id(reply.id)
      assert updated.status == :sending
    end

    test "marks reply as failed when delivery fails on final attempt" do
      email = MessagingFixtures.inbound_email_fixture()
      reply = MessagingFixtures.email_reply_fixture(%{inbound_email_id: email.id})
      StubMailerAdapter.fail_with({:network, :timeout})

      assert {:error, _reason} =
               SendEmailReplyWorker.perform(%Oban.Job{
                 args: %{"reply_id" => reply.id},
                 attempt: 3,
                 max_attempts: 3
               })

      {:ok, updated} = Messaging.get_email_reply_by_id(reply.id)
      assert updated.status == :failed
    end
  end
end
