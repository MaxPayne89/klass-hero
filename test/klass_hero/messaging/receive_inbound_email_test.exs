defmodule KlassHero.Messaging.ReceiveInboundEmailTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.Messaging.ReceiveInboundEmail
  alias KlassHero.Messaging.ResendEmailContentAdapter
  alias KlassHero.MessagingFixtures

  setup do
    Req.Test.stub(ResendEmailContentAdapter, fn conn ->
      Req.Test.json(conn, %{
        "html" => "<p>Fetched</p>",
        "text" => "Fetched",
        "headers" => %{}
      })
    end)

    :ok
  end

  describe "execute/1" do
    test "stores email with message_id and content_status pending" do
      attrs =
        MessagingFixtures.valid_inbound_email_attrs(%{
          message_id: "<test-msg@example.com>",
          content_status: "pending",
          body_html: nil,
          body_text: nil
        })

      assert {:ok, email} = ReceiveInboundEmail.execute(attrs)
      assert email.message_id == "<test-msg@example.com>"
      assert email.content_status == :pending
    end

    test "enqueues content fetch job after storing" do
      attrs =
        MessagingFixtures.valid_inbound_email_attrs(%{
          content_status: "pending",
          body_html: nil,
          body_text: nil
        })

      assert {:ok, email} = ReceiveInboundEmail.execute(attrs)
      assert email.id != nil
    end

    test "returns duplicate for already-stored email" do
      attrs = MessagingFixtures.valid_inbound_email_attrs()
      assert {:ok, _} = ReceiveInboundEmail.execute(attrs)
      assert {:ok, :duplicate} = ReceiveInboundEmail.execute(attrs)
    end
  end
end
