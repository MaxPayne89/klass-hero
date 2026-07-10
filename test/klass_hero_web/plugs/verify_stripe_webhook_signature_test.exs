defmodule KlassHeroWeb.Plugs.VerifyStripeWebhookSignatureTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias KlassHeroWeb.Plugs.VerifyStripeWebhookSignature

  @raw_body ~s({"type":"identity.verification_session.verified","data":{"object":{"id":"vs_1"}}})

  setup do
    secret = "whsec_#{Base.encode16(:crypto.strong_rand_bytes(16))}"

    original_verify = Application.get_env(:klass_hero, :verify_webhook_signature)
    original_secret = Application.get_env(:klass_hero, :stripe_webhook_secret)

    Application.put_env(:klass_hero, :verify_webhook_signature, true)
    Application.put_env(:klass_hero, :stripe_webhook_secret, secret)

    on_exit(fn ->
      restore_env(:verify_webhook_signature, original_verify)
      restore_env(:stripe_webhook_secret, original_secret)
    end)

    %{secret: secret}
  end

  defp restore_env(key, nil), do: Application.delete_env(:klass_hero, key)
  defp restore_env(key, value), do: Application.put_env(:klass_hero, key, value)

  defp base_conn, do: conn(:post, "/webhooks/stripe") |> assign(:raw_body, @raw_body)

  defp sign(secret, timestamp, body) do
    :crypto.mac(:hmac, :sha256, secret, "#{timestamp}.#{body}") |> Base.encode16(case: :lower)
  end

  defp header(timestamp, signature), do: "t=#{timestamp},v1=#{signature}"

  defp now, do: Integer.to_string(System.system_time(:second))

  describe "call/2 — bypass" do
    test "passes through without checking when verification is disabled" do
      Application.put_env(:klass_hero, :verify_webhook_signature, false)
      conn = conn(:post, "/webhooks/stripe") |> VerifyStripeWebhookSignature.call([])
      refute conn.halted
    end
  end

  describe "call/2 — valid signature" do
    test "passes with a correctly computed Stripe signature", %{secret: secret} do
      ts = now()

      conn =
        base_conn()
        |> put_req_header("stripe-signature", header(ts, sign(secret, ts, @raw_body)))
        |> VerifyStripeWebhookSignature.call([])

      refute conn.halted
    end

    test "accepts a matching v1 when a rotated signature is also present", %{secret: secret} do
      ts = now()
      good = sign(secret, ts, @raw_body)

      conn =
        base_conn()
        |> put_req_header("stripe-signature", "t=#{ts},v1=deadbeef,v1=#{good}")
        |> VerifyStripeWebhookSignature.call([])

      refute conn.halted
    end
  end

  describe "call/2 — rejection" do
    test "halts with 401 when the signature does not match" do
      ts = now()

      conn =
        base_conn()
        |> put_req_header("stripe-signature", header(ts, sign("whsec_wrong", ts, @raw_body)))
        |> VerifyStripeWebhookSignature.call([])

      assert conn.halted
      assert conn.status == 401
    end

    test "halts when the signature is over a different body", %{secret: secret} do
      ts = now()

      conn =
        base_conn()
        |> put_req_header("stripe-signature", header(ts, sign(secret, ts, ~s({"tampered":1}))))
        |> VerifyStripeWebhookSignature.call([])

      assert conn.halted
    end

    test "halts when the stripe-signature header is missing" do
      conn = base_conn() |> VerifyStripeWebhookSignature.call([])
      assert conn.halted
      assert conn.status == 401
    end

    test "halts when raw_body is not assigned", %{secret: secret} do
      ts = now()

      conn =
        conn(:post, "/webhooks/stripe")
        |> put_req_header("stripe-signature", header(ts, sign(secret, ts, @raw_body)))
        |> VerifyStripeWebhookSignature.call([])

      assert conn.halted
    end

    test "halts when the timestamp is older than 5 minutes", %{secret: secret} do
      ts = Integer.to_string(System.system_time(:second) - 361)

      conn =
        base_conn()
        |> put_req_header("stripe-signature", header(ts, sign(secret, ts, @raw_body)))
        |> VerifyStripeWebhookSignature.call([])

      assert conn.halted
    end

    test "halts when the timestamp is not an integer", %{secret: secret} do
      conn =
        base_conn()
        |> put_req_header("stripe-signature", header("nope", sign(secret, "nope", @raw_body)))
        |> VerifyStripeWebhookSignature.call([])

      assert conn.halted
    end

    test "halts when the webhook secret is not configured" do
      Application.delete_env(:klass_hero, :stripe_webhook_secret)
      ts = now()

      conn =
        base_conn()
        |> put_req_header("stripe-signature", header(ts, "whatever"))
        |> VerifyStripeWebhookSignature.call([])

      assert conn.halted
    end
  end
end
