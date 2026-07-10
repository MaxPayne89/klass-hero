defmodule KlassHero.Provider.StripeIdentityTest do
  use ExUnit.Case, async: true

  alias KlassHero.Provider.StripeIdentity

  @params %{provider_id: "prov-1", return_url: "https://klasshero.test/provider/verification"}

  describe "create_session/1" do
    test "a 200 returns the Stripe session id and hosted url" do
      Req.Test.stub(StripeIdentity, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/v1/identity/verification_sessions"

        Req.Test.json(conn, %{
          "id" => "vs_123",
          "url" => "https://verify.stripe.com/start/vs_123",
          "status" => "requires_input"
        })
      end)

      assert {:ok, %{session_id: "vs_123", url: "https://verify.stripe.com/start/vs_123"}} =
               StripeIdentity.create_session(@params)
    end

    test "a 4xx maps to a client error" do
      Req.Test.stub(StripeIdentity, fn conn ->
        conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"error" => %{"message" => "bad"}})
      end)

      assert {:error, {:client_error, 400}} = StripeIdentity.create_session(@params)
    end

    test "a 5xx maps to a server error" do
      Req.Test.stub(StripeIdentity, fn conn ->
        conn |> Plug.Conn.put_status(503) |> Req.Test.json(%{"error" => %{}})
      end)

      assert {:error, :server_error} = StripeIdentity.create_session(@params)
    end

    test "a missing secret key short-circuits with :stripe_not_configured" do
      original = Application.get_env(:klass_hero, :stripe)
      Application.put_env(:klass_hero, :stripe, secret_key: nil)
      on_exit(fn -> Application.put_env(:klass_hero, :stripe, original) end)

      assert {:error, :stripe_not_configured} = StripeIdentity.create_session(@params)
    end
  end
end
