defmodule KlassHero.Messaging.NewMessageEmailHandlerTest do
  @moduledoc """
  Turns one `message_sent` event into one email job per participant who should
  get one.

  Events are built through `Messaging.Events.message_sent/7` rather than
  hand-rolled maps, so a change to the real payload shape fails here instead of
  passing against a fixture that no producer emits.
  """
  use KlassHero.DataCase, async: true

  import KlassHero.Factory

  alias KlassHero.Accounts
  alias KlassHero.AccountsFixtures
  alias KlassHero.Messaging.Events
  alias KlassHero.Messaging.NewMessageEmailHandler
  alias KlassHero.Messaging.Workers.NewMessageEmailWorker

  defp participant(conversation, opts \\ []) do
    user = AccountsFixtures.user_fixture()

    insert(
      :participant_schema,
      Keyword.merge(
        [conversation_id: conversation.id, user_id: user.id, last_read_at: DateTime.utc_now()],
        opts
      )
    )

    user
  end

  defp message(conversation, sender, opts \\ []) do
    insert(
      :message_schema,
      Keyword.merge(
        [conversation_id: conversation.id, sender_id: sender.id, content: "hello"],
        opts
      )
    )
  end

  defp event(message, opts \\ []) do
    Events.message_sent(
      message.conversation_id,
      message.id,
      message.sender_id,
      Keyword.get(opts, :content, message.content),
      Keyword.get(opts, :message_type, :text),
      message.inserted_at,
      []
    )
  end

  defp handle(event) do
    Oban.Testing.with_testing_mode(:manual, fn -> NewMessageEmailHandler.handle_event(event) end)
  end

  defp enqueued_recipient_ids do
    Oban.Job
    |> KlassHero.Repo.all()
    |> Enum.filter(&(&1.worker == Oban.Worker.to_string(NewMessageEmailWorker)))
    |> Enum.map(& &1.args["recipient_user_id"])
    |> Enum.sort()
  end

  describe "handle_event/1 — who gets a job" do
    test "one per active participant, excluding the sender" do
      conversation = insert(:conversation_schema)
      sender = participant(conversation)
      recipient_a = participant(conversation)
      recipient_b = participant(conversation)

      assert :ok = conversation |> message(sender) |> event() |> handle()

      assert enqueued_recipient_ids() == Enum.sort([recipient_a.id, recipient_b.id])
    end

    test "nobody who has opted out" do
      conversation = insert(:conversation_schema)
      sender = participant(conversation)
      wants = participant(conversation)
      declines = participant(conversation)

      {:ok, _} =
        Accounts.update_user_email_notification_preference(declines, :new_message_email, false)

      assert :ok = conversation |> message(sender) |> event() |> handle()

      assert enqueued_recipient_ids() == [wants.id]
    end

    test "nobody who has left the conversation" do
      conversation = insert(:conversation_schema)
      sender = participant(conversation)
      stayed = participant(conversation)
      _left = participant(conversation, left_at: DateTime.utc_now())

      assert :ok = conversation |> message(sender) |> event() |> handle()

      assert enqueued_recipient_ids() == [stayed.id]
    end

    # A "[broadcast:…] Re: …" marker is written by ReplyPrivatelyToBroadcast
    # through the same send path, so it stages a real message_sent. Emailing on
    # it would notify the provider twice for one parent action.
    test "nothing at all for a system message" do
      conversation = insert(:conversation_schema)
      sender = participant(conversation)
      _recipient = participant(conversation)

      message = message(conversation, sender, message_type: :system)

      assert :ok = message |> event(message_type: :system) |> handle()

      assert enqueued_recipient_ids() == []
    end
  end

  describe "handle_event/1 — already-unread suppression" do
    test "skips a participant who has not caught up on this conversation" do
      conversation = insert(:conversation_schema)
      sender = participant(conversation)
      caught_up = participant(conversation)
      _behind = participant(conversation, last_read_at: ~U[2020-01-01 00:00:00Z])

      # An earlier message that `behind` has not read and `caught_up` has.
      message(conversation, sender, inserted_at: ~U[2021-01-01 00:00:00Z])

      assert :ok = conversation |> message(sender) |> event() |> handle()

      assert enqueued_recipient_ids() == [caught_up.id],
             "a participant already sitting on unread mail was emailed again"
    end

    test "still notifies someone who has never read but has no earlier messages" do
      conversation = insert(:conversation_schema)
      sender = participant(conversation)
      newcomer = participant(conversation, last_read_at: nil)

      assert :ok = conversation |> message(sender) |> event() |> handle()

      assert enqueued_recipient_ids() == [newcomer.id]
    end

    test "a soft-deleted earlier message does not count as unread" do
      conversation = insert(:conversation_schema)
      sender = participant(conversation)
      recipient = participant(conversation, last_read_at: ~U[2020-01-01 00:00:00Z])

      message(conversation, sender,
        inserted_at: ~U[2021-01-01 00:00:00Z],
        deleted_at: ~U[2021-01-02 00:00:00Z]
      )

      assert :ok = conversation |> message(sender) |> event() |> handle()

      assert enqueued_recipient_ids() == [recipient.id]
    end
  end

  describe "handle_event/1 — job args" do
    test "carry ids only, never the message body or an address" do
      conversation = insert(:conversation_schema)
      sender = participant(conversation)
      recipient = participant(conversation)

      message = message(conversation, sender, content: "a private medical detail")
      assert :ok = message |> event() |> handle()

      [job] =
        Oban.Job
        |> KlassHero.Repo.all()
        |> Enum.filter(&(&1.worker == Oban.Worker.to_string(NewMessageEmailWorker)))

      assert job.args["conversation_id"] == conversation.id
      assert job.args["recipient_user_id"] == recipient.id

      encoded = Jason.encode!(job.args)
      refute encoded =~ "a private medical detail"
      refute encoded =~ recipient.email
    end
  end

  describe "wiring" do
    test "declares the event the registry routes to it" do
      assert NewMessageEmailHandler.subscribed_events() == [:message_sent]
    end

    test "ignores anything else" do
      assert :ignore = NewMessageEmailHandler.handle_event(%{event_type: :conversation_created})
    end
  end
end
