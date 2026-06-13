defmodule KlassHeroWeb.Plugs.VerifyWebhookSignature do
  @moduledoc """
  Verifies Resend webhook signatures using the Svix protocol.

  Svix protocol:
  1. Construct message: "${svix_id}.${svix_timestamp}.${raw_body}"
  2. Decode base64 secret (strip "whsec_" prefix)
  3. HMAC-SHA256 the message with decoded secret
  4. Base64-encode result
  5. Compare with signatures in svix-signature header (space-separated, v1, prefixed)
  6. Reject if timestamp older than 5 minutes
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
    secret = Application.get_env(:klass_hero, :resend_webhook_secret)
    raw_body = conn.assigns[:raw_body]
    svix_id = get_req_header(conn, "svix-id") |> List.first()
    svix_timestamp = get_req_header(conn, "svix-timestamp") |> List.first()
    svix_signature = get_req_header(conn, "svix-signature") |> List.first()

    with {:ok, _} <-
           validate_required(secret, raw_body, svix_id, svix_timestamp, svix_signature),
         {:ok, _} <- validate_timestamp(svix_timestamp),
         {:ok, _} <-
           validate_signature(secret, raw_body, svix_id, svix_timestamp, svix_signature) do
      conn
    else
      {:error, reason} ->
        conn
        |> put_status(401)
        |> Phoenix.Controller.json(%{error: reason})
        |> halt()
    end
  end

  defp validate_required(secret, raw_body, svix_id, svix_timestamp, svix_signature) do
    if secret && raw_body && svix_id && svix_timestamp && svix_signature do
      {:ok, :valid}
    else
      {:error, "missing signature headers or secret"}
    end
  end

  defp validate_timestamp(svix_timestamp) do
    case Integer.parse(svix_timestamp) do
      {ts, ""} ->
        now = System.system_time(:second)

        if abs(now - ts) <= @max_timestamp_age do
          {:ok, :valid}
        else
          {:error, "timestamp too old"}
        end

      _ ->
        {:error, "invalid timestamp"}
    end
  end

  defp validate_signature(secret, raw_body, svix_id, svix_timestamp, svix_signature) do
    stripped = String.replace_prefix(secret, "whsec_", "")

    case Base.decode64(stripped) do
      {:ok, secret_bytes} ->
        signed_content = "#{svix_id}.#{svix_timestamp}.#{raw_body}"

        expected =
          :crypto.mac(:hmac, :sha256, secret_bytes, signed_content)
          |> Base.encode64()

        # Resend may send multiple signatures during key rotation; any match is sufficient.
        signatures =
          svix_signature
          |> String.split(" ")
          |> Enum.map(fn sig -> String.replace_prefix(sig, "v1,", "") end)

        if Enum.any?(signatures, &Plug.Crypto.secure_compare(&1, expected)) do
          {:ok, :valid}
        else
          {:error, "invalid signature"}
        end

      :error ->
        {:error, "invalid webhook secret configuration"}
    end
  end
end
