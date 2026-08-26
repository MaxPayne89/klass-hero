defmodule KlassHero.Messaging.NewMessageEmailDeliveryTest do
  @moduledoc """
  The whole path, once: sending a message stages `message_sent` in the same
  transaction as the write, the delivery job routes it to
  `NewMessageEmailHandler`, and the email job that handler enqueues actually
  reaches a mailbox.

  The rest of the messaging suite runs against `TestOutbox`, which records what
  a producer staged but never runs a consumer — so nothing else in the suite
  would notice if this consumer were unregistered, or if the handler and the
  real payload disagreed about a key. This swaps in the real `ObanOutbox` for
  the length of one send, following `archive_conversations_delivery_test.exs`.
  """
  use KlassHero.DataCase, async: false

  import KlassHero.EmailTestHelper
  import KlassHero.Factory
  import Swoosh.TestAssertions

  alias KlassHero.Accounts
  alias KlassHero.AccountsFixtures
  alias KlassHero.Messaging
  alias KlassHero.Shared.Adapters.Driven.Events.ObanOutbox

  setup do
    provider = insert(:provider_profile_schema)
    conversation = insert(:conversation_schema, provider_id: provider.id)

    sender = AccountsFixtures.user_fixture()
    recipient = AccountsFixtures.user_fixture()

    for user <- [sender, recipient] do
      insert(:participant_schema,
        conversation_id: conversation.id,
        user_id: user.id,
        last_read_at: DateTime.utc_now()
      )
    end

    %{conversation: conversation, sender: sender, recipient: recipient}
  end

  test "a sent message reaches the other participant's mailbox as a link", ctx do
    send_and_deliver(ctx.conversation.id, ctx.sender.id)

    # assert_email_sent/1 asserts on this callback's return value, and ExUnit's
    # refute/2 returns false when it passes — so the last expression here has to
    # be an assert, or the whole assertion fails whatever the email says.
    assert_email_sent(fn email ->
      assert [{_name, address}] = email.to
      assert address == ctx.recipient.email

      refute email.text_body =~ "the actual message text",
             "the notification quoted the message body"

      assert email.text_body =~ "/messages/#{ctx.conversation.id}"
    end)
  end

  test "nothing is sent to someone who switched the notification off", ctx do
    {:ok, _} =
      Accounts.update_user_email_notification_preference(
        ctx.recipient,
        :new_message_email,
        false
      )

    send_and_deliver(ctx.conversation.id, ctx.sender.id)

    assert_no_email_sent()
  end

  # The real outbox is swapped in around the act alone: under ObanOutbox the
  # user fixtures would also deliver their own user_registered, which creates a
  # provider profile that collides with the factory's.
  #
  # Manual mode then drain, because `testing: :inline` would run the delivery
  # job at insert — inside SendMessage's own transaction, which is a sequencing
  # production never has.
  defp send_and_deliver(conversation_id, sender_id) do
    original_outbox = Application.get_env(:klass_hero, :outbox)
    Application.put_env(:klass_hero, :outbox, module: ObanOutbox)

    # Drain before the act, not only after: the fixtures above staged jobs of
    # their own, and leaving them queued lets them replay into this assertion.
    flush_emails()

    try do
      {:ok, _message} =
        Oban.Testing.with_testing_mode(:manual, fn ->
          Messaging.send_message(conversation_id, sender_id, "the actual message text")
        end)
    after
      Application.put_env(:klass_hero, :outbox, original_outbox)
    end

    Oban.drain_queue(queue: :events, with_recursion: true)
    Oban.drain_queue(queue: :email, with_recursion: true)
  end
end
