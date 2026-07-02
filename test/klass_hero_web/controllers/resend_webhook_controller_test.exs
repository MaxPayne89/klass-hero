defmodule KlassHeroWeb.ResendWebhookControllerTest do
  use KlassHeroWeb.ConnCase, async: true

  alias KlassHero.Messaging
  alias KlassHero.Messaging.Adapters.Driven.ResendEmailContentAdapter

  @valid_payload %{
    "type" => "email.received",
    "data" => %{
      "email_id" => "resend_test_#{System.unique_integer([:positive])}",
      "from" => "sender@example.com",
      "to" => ["hello@mail.klasshero.com"],
      "subject" => "Test Email",
      "html" => "<p>Hello</p>",
      "text" => "Hello",
      "headers" => [%{"name" => "Message-ID", "value" => "<abc@example.com>"}],
      "created_at" => "2026-03-20T10:00:00Z"
    }
  }

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

  describe "POST /webhooks/resend" do
    test "returns 200 for valid email.received event", %{conn: conn} do
      conn = post(conn, ~p"/webhooks/resend", @valid_payload)
      assert json_response(conn, 200)
    end

    test "returns 200 for duplicate (idempotent)", %{conn: conn} do
      payload =
        put_in(@valid_payload, ["data", "email_id"], "dup_#{System.unique_integer([:positive])}")

      post(conn, ~p"/webhooks/resend", payload)
      conn2 = post(conn, ~p"/webhooks/resend", payload)
      assert json_response(conn2, 200)
    end

    test "returns 200 for unhandled event types", %{conn: conn} do
      payload = %{"type" => "email.delivered", "data" => %{}}
      conn = post(conn, ~p"/webhooks/resend", payload)
      assert json_response(conn, 200)
    end

    test "stores message_id from webhook payload", %{conn: conn} do
      resend_id = "msg_id_test_#{System.unique_integer([:positive])}"

      payload = %{
        "type" => "email.received",
        "data" => %{
          "email_id" => resend_id,
          "from" => "sender@example.com",
          "to" => ["hello@mail.klasshero.com"],
          "subject" => "Threading Test",
          "message_id" => "<thread-test@gmail.com>",
          "created_at" => "2026-03-21T10:00:00Z"
        }
      }

      post(conn, ~p"/webhooks/resend", payload)

      {:ok, email} = Messaging.get_inbound_email_by_resend_id(resend_id)
      assert email.message_id == "<thread-test@gmail.com>"
    end
  end
end
