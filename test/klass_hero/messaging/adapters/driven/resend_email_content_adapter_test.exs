defmodule KlassHero.Messaging.Adapters.Driven.ResendEmailContentAdapterTest do
  # async: false — the interaction telemetry handler is global, so a concurrent
  # module's interaction events would cross-talk into this test's assert_receive.
  use ExUnit.Case, async: false

  alias KlassHero.Messaging.Adapters.Driven.ResendEmailContentAdapter

  setup do
    test_pid = self()
    ref = make_ref()

    :telemetry.attach_many(
      {__MODULE__, ref},
      [
        [:klass_hero, :interaction, :start],
        [:klass_hero, :interaction, :stop],
        [:klass_hero, :interaction, :exception]
      ],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end,
      %{}
    )

    on_exit(fn -> :telemetry.detach({__MODULE__, ref}) end)

    Req.Test.stub(ResendEmailContentAdapter, fn conn ->
      case conn.path_info do
        ["emails", "receiving", "success-id"] ->
          Req.Test.json(conn, %{
            "html" => "<p>Hello</p>",
            "text" => "Hello",
            "headers" => %{"Message-ID" => "<abc@example.com>"}
          })

        ["emails", "receiving", "not-found-id"] ->
          conn
          |> Plug.Conn.put_status(404)
          |> Req.Test.json(%{"message" => "Not found"})

        ["emails", "receiving", "rate-limited-id"] ->
          conn
          |> Plug.Conn.put_status(429)
          |> Req.Test.json(%{"message" => "Rate limited"})

        ["emails", "receiving", "server-error-id"] ->
          conn
          |> Plug.Conn.put_status(500)
          |> Req.Test.json(%{"message" => "Internal error"})
      end
    end)

    :ok
  end

  describe "fetch_content/1" do
    test "returns content on success with normalized headers" do
      assert {:ok, content} = ResendEmailContentAdapter.fetch_content("success-id")
      assert content.html == "<p>Hello</p>"
      assert content.text == "Hello"
      assert content.headers == [%{"name" => "Message-ID", "value" => "<abc@example.com>"}]
    end

    test "returns :not_found on 404" do
      assert {:error, :not_found} = ResendEmailContentAdapter.fetch_content("not-found-id")
    end

    test "returns :rate_limited on 429" do
      assert {:error, :rate_limited} = ResendEmailContentAdapter.fetch_content("rate-limited-id")
    end

    test "returns :server_error on 5xx" do
      assert {:error, :server_error} = ResendEmailContentAdapter.fetch_content("server-error-id")
    end
  end

  describe "interaction telemetry" do
    test "emits a :stop event with :http kind and :ok status on success" do
      assert {:ok, _content} = ResendEmailContentAdapter.fetch_content("success-id")

      assert_receive {:telemetry, [:klass_hero, :interaction, :stop], %{duration_us: _},
                      %{
                        io_kind: :http,
                        operation: :fetch_email_content,
                        status: :ok,
                        attributes: %{"http.service" => "resend"}
                      }}
    end

    test "emits a :stop event with :error status and normalised error on 404" do
      assert {:error, :not_found} = ResendEmailContentAdapter.fetch_content("not-found-id")

      assert_receive {:telemetry, [:klass_hero, :interaction, :stop], _measurements,
                      %{io_kind: :http, operation: :fetch_email_content, status: :error, error: :not_found}}
    end
  end
end
