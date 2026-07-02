defmodule KlassHero.Messaging.Adapters.Driving.Workers.FetchEmailContentWorkerTest do
  use KlassHero.DataCase, async: true

  alias KlassHero.Messaging
  alias KlassHero.Messaging.Adapters.Driven.ResendEmailContentAdapter
  alias KlassHero.Messaging.Adapters.Driving.Workers.FetchEmailContentWorker
  alias KlassHero.MessagingFixtures

  setup do
    email =
      MessagingFixtures.inbound_email_fixture(%{
        content_status: "pending",
        body_html: nil,
        body_text: nil
      })

    %{email: email}
  end

  describe "perform/1" do
    test "fetches content and updates email to fetched", %{email: email} do
      Req.Test.stub(ResendEmailContentAdapter, fn conn ->
        Req.Test.json(conn, %{
          "html" => "<p>Fetched body</p>",
          "text" => "Fetched body",
          "headers" => %{"Message-ID" => "<abc@example.com>"}
        })
      end)

      assert :ok =
               FetchEmailContentWorker.perform(%Oban.Job{
                 args: %{"email_id" => email.id, "resend_id" => email.resend_id}
               })

      {:ok, updated} = Messaging.get_inbound_email_by_id(email.id)
      assert updated.content_status == :fetched
      assert updated.body_html == "<p>Fetched body</p>"
      assert updated.body_text == "Fetched body"
    end

    test "marks email as failed when content fetch fails", %{email: email} do
      Req.Test.stub(ResendEmailContentAdapter, fn conn ->
        conn
        |> Plug.Conn.put_status(404)
        |> Req.Test.json(%{"message" => "Not found"})
      end)

      assert {:error, :not_found} =
               FetchEmailContentWorker.perform(%Oban.Job{
                 args: %{"email_id" => email.id, "resend_id" => email.resend_id},
                 attempt: 3,
                 max_attempts: 3
               })
    end
  end
end
