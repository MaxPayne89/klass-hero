defmodule KlassHero.Messaging.Workers.NewMessageEmailWorkerTest do
  @moduledoc """
  Delivery of one new-message notice.

  The worker re-checks the preference rather than trusting the enqueue, so the
  interesting cases here are the ones where the world changed between the two.
  """
  use KlassHero.DataCase, async: true

  import KlassHero.EmailTestHelper
  import Swoosh.TestAssertions

  alias KlassHero.Accounts
  alias KlassHero.AccountsFixtures
  alias KlassHero.Messaging.Workers.NewMessageEmailWorker
  alias KlassHero.Test.StubMailerAdapter

  setup do
    # user_fixture/1 delivers a magic-link email as a side effect; without this
    # the assertions below would match that one instead.
    on_exit(&StubMailerAdapter.deliver_normally/0)
    :ok
  end

  defp job(user_id, conversation_id \\ Ecto.UUID.generate()) do
    %Oban.Job{
      args: %{"conversation_id" => conversation_id, "recipient_user_id" => user_id}
    }
  end

  describe "execute/1" do
    test "emails a link, and never the conversation's content" do
      user = AccountsFixtures.user_fixture()
      conversation_id = Ecto.UUID.generate()
      flush_emails()

      assert :ok = NewMessageEmailWorker.execute(job(user.id, conversation_id))

      assert_email_sent(fn email ->
        assert {_name, address} = email.to |> List.first()
        assert address == user.email
        assert email.subject =~ "new message"
        assert email.text_body =~ "/messages/#{conversation_id}"
        assert email.html_body =~ "/messages/#{conversation_id}"
      end)
    end

    # The enqueue already filtered, but a broadcast's jobs can sit on a
    # rate-limited queue long enough for someone to change their mind.
    test "sends nothing when the user opted out after the job was enqueued" do
      user = AccountsFixtures.user_fixture()
      {:ok, _} = Accounts.update_user_email_notification_preference(user, :new_message_email, false)
      flush_emails()

      assert :ok = NewMessageEmailWorker.execute(job(user.id))

      assert_no_email_sent()
    end

    # Completed, not failed: retrying cannot make a deleted account exist.
    test "sends nothing when the recipient no longer exists" do
      flush_emails()

      assert :ok = NewMessageEmailWorker.execute(job(Ecto.UUID.generate()))

      assert_no_email_sent()
    end

    test "reports an error when delivery fails, so Oban retries" do
      user = AccountsFixtures.user_fixture()
      flush_emails()
      StubMailerAdapter.fail_with({:network, :timeout})

      assert {:error, _reason} = NewMessageEmailWorker.execute(job(user.id))
    end
  end
end
