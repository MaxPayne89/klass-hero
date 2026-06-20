defmodule KlassHero.Provider.Adapters.Driven.StripeIdentityAdapterTest do
  # async: false — the interaction telemetry handler is global (mirrors ResendEmailContentAdapterTest).
  use ExUnit.Case, async: false

  alias KlassHero.Provider.Adapters.Driven.StripeIdentityAdapter

  @params %{provider_id: "prov-1", return_url: "https://klasshero.test/provider/verification"}

  describe "create_session/1" do
    test "a 200 returns the Stripe session id and hosted url" do
      Req.Test.stub(StripeIdentityAdapter, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/v1/identity/verification_sessions"

        Req.Test.json(conn, %{
          "id" => "vs_123",
          "url" => "https://verify.stripe.com/start/vs_123",
          "status" => "requires_input"
        })
      end)

      assert {:ok, %{session_id: "vs_123", url: "https://verify.stripe.com/start/vs_123"}} =
               StripeIdentityAdapter.create_session(@params)
    end

    test "a 4xx maps to a client error" do
      Req.Test.stub(StripeIdentityAdapter, fn conn ->
        conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"error" => %{"message" => "bad"}})
      end)

      assert {:error, {:client_error, 400}} = StripeIdentityAdapter.create_session(@params)
    end

    test "a 5xx maps to a server error" do
      Req.Test.stub(StripeIdentityAdapter, fn conn ->
        conn |> Plug.Conn.put_status(503) |> Req.Test.json(%{"error" => %{}})
      end)

      assert {:error, :server_error} = StripeIdentityAdapter.create_session(@params)
    end

    test "a missing secret key short-circuits with :stripe_not_configured" do
      original = Application.get_env(:klass_hero, :stripe)
      Application.put_env(:klass_hero, :stripe, secret_key: nil)
      on_exit(fn -> Application.put_env(:klass_hero, :stripe, original) end)

      assert {:error, :stripe_not_configured} = StripeIdentityAdapter.create_session(@params)
    end
  end
end
