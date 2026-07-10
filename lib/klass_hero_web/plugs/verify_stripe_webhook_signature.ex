defmodule KlassHeroWeb.Plugs.VerifyStripeWebhookSignature do
  @moduledoc """
  Verifies Stripe webhook signatures (the `Stripe-Signature` scheme).

  Stripe protocol:
  1. The `Stripe-Signature` header is a comma-separated list: `t=<timestamp>,v1=<signature>`
     (it may carry several `v1` entries during key rotation).
  2. Build the signed payload `"<timestamp>.<raw_body>"`.
  3. HMAC-SHA256 it with the endpoint signing secret (`whsec_…`), used as-is — Stripe does
     NOT base64-decode the secret (that is the Svix/Resend scheme).
  4. Hex-encode and constant-time compare against any `v1` in the header.
  5. Reject if the timestamp is older than 5 minutes.

  Honors the shared `:verify_webhook_signature` flag so test/dev can bypass verification.
  """

  import Plug.Conn

  # 5 minutes in seconds
  @max_timestamp_age 300

  def init(opts), do: opts

  def call(conn, _opts) do
    if Application.get_env(:klass_hero, :verify_webhook_signature, true) do
      verify(conn)
    else
      conn
    end
  end

  defp verify(conn) do
    secret = Application.get_env(:klass_hero, :stripe_webhook_secret)
    raw_body = conn.assigns[:raw_body]
    header = get_req_header(conn, "stripe-signature") |> List.first()

    with {:ok, timestamp, signatures} <- parse_header(header),
         :ok <- validate_required(secret, raw_body),
         :ok <- validate_timestamp(timestamp),
         :ok <- validate_signature(secret, raw_body, timestamp, signatures) do
      conn
    else
      {:error, reason} ->
        conn
        |> put_status(401)
        |> Phoenix.Controller.json(%{error: reason})
        |> halt()
    end
  end

  defp parse_header(nil), do: {:error, "missing signature header"}

  defp parse_header(header) do
    parts =
      header
      |> String.split(",")
      |> Enum.map(fn part -> part |> String.trim() |> String.split("=", parts: 2) end)

    timestamp = Enum.find_value(parts, fn ["t", value] -> value end)
    signatures = for ["v1", value] <- parts, do: value

    if timestamp && signatures != [] do
      {:ok, timestamp, signatures}
    else
      {:error, "malformed signature header"}
    end
  end

  defp validate_required(secret, raw_body) do
    if secret && raw_body, do: :ok, else: {:error, "missing body or secret"}
  end

  defp validate_timestamp(timestamp) do
    case Integer.parse(timestamp) do
      {ts, ""} ->
        if abs(System.system_time(:second) - ts) <= @max_timestamp_age,
          do: :ok,
          else: {:error, "timestamp too old"}

      _ ->
        {:error, "invalid timestamp"}
    end
  end

  defp validate_signature(secret, raw_body, timestamp, signatures) do
    expected =
      :crypto.mac(:hmac, :sha256, secret, "#{timestamp}.#{raw_body}")
      |> Base.encode16(case: :lower)

    if Enum.any?(signatures, &Plug.Crypto.secure_compare(&1, expected)) do
      :ok
    else
      {:error, "invalid signature"}
    end
  end
end
