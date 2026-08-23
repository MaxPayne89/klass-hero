defmodule KlassHero.Messaging.Workers.SendEmailReplyWorkerTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.Messaging
  alias KlassHero.Messaging.Workers.SendEmailReplyWorker
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
                 # `id` and `worker` because this attempt reaches the compensation gate,
                 # which keys its marker on them — a job that gets there came out of
                 # `oban_jobs` and always has both (#1339).
                 id: System.unique_integer([:positive]),
                 worker: Oban.Worker.to_string(SendEmailReplyWorker),
                 args: %{"reply_id" => reply.id},
                 attempt: 3,
                 max_attempts: 3
               })

      {:ok, updated} = Messaging.get_email_reply_by_id(reply.id)
      assert updated.status == :failed
    end

    # This branch discards instead of retrying, so gating its compensation on
    # final_attempt?/1 meant a first-attempt discard could never compensate. Reaching it
    # with a reply still present requires the inbound email to vanish from under a live
    # reply, which `on_delete: :delete_all` prevents — so the compensation has nothing to
    # mark and must report that quietly rather than raise.
    test "discards without raising when the reply is gone" do
      assert {:discard, :not_found} =
               SendEmailReplyWorker.perform(%Oban.Job{
                 args: %{"reply_id" => Ecto.UUID.generate()},
                 attempt: 1,
                 max_attempts: 3
               })
    end
  end

  describe "compensate/2" do
    test "marks the reply failed regardless of which attempt discovered the failure" do
      email = MessagingFixtures.inbound_email_fixture()
      reply = MessagingFixtures.email_reply_fixture(%{inbound_email_id: email.id})

      assert :ok =
               SendEmailReplyWorker.compensate(
                 %Oban.Job{args: %{"reply_id" => reply.id}, attempt: 1, max_attempts: 3},
                 :whatever
               )

      {:ok, updated} = Messaging.get_email_reply_by_id(reply.id)
      assert updated.status == :failed
    end

    # The sweep replays compensation for any discarded job it has not yet recorded. If a
    # duplicate attempt delivered the reply in the meantime, that replay must not record
    # the delivered reply as failed — and must not report an error the sweep would retry.
    test "reports :ignore rather than overwriting a delivered reply" do
      email = MessagingFixtures.inbound_email_fixture()
      reply = MessagingFixtures.email_reply_fixture(%{inbound_email_id: email.id})
      {:ok, _sent} = Messaging.update_email_reply_status(reply.id, "sent", %{})

      assert :ignore =
               SendEmailReplyWorker.compensate(%Oban.Job{args: %{"reply_id" => reply.id}}, :whatever)

      {:ok, unchanged} = Messaging.get_email_reply_by_id(reply.id)
      assert unchanged.status == :sent
    end

    test "reports :ignore when the reply no longer exists" do
      assert :ignore =
               SendEmailReplyWorker.compensate(
                 %Oban.Job{args: %{"reply_id" => Ecto.UUID.generate()}},
                 :whatever
               )
    end
  end
end
