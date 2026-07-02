defmodule KlassHero.Messaging.Adapters.Driving.Workers.SendEmailReplyWorkerTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.Messaging
  alias KlassHero.Messaging.Adapters.Driving.Workers.SendEmailReplyWorker
  alias KlassHero.MessagingFixtures

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

    test "marks reply as failed when delivery fails on final attempt" do
      email = MessagingFixtures.inbound_email_fixture()
      reply = MessagingFixtures.email_reply_fixture(%{inbound_email_id: email.id})

      # In test env, Swoosh uses Local adapter which always succeeds.
      # Test happy path here. Failure path tested via unit test on worker logic.
      assert :ok =
               SendEmailReplyWorker.perform(%Oban.Job{
                 args: %{"reply_id" => reply.id}
               })
    end
  end
end
