defmodule KlassHeroWeb.ResendWebhookController do
  use KlassHeroWeb, :controller

  alias KlassHero.Messaging

  require Logger

  def handle(conn, %{"type" => "email.received", "data" => data}) do
    attrs = %{
      resend_id: data["email_id"],
      from_address: data["from"],
      from_name: data["from_name"],
      to_addresses: data["to"] || [],
      cc_addresses: data["cc"] || [],
      subject: data["subject"] || "(no subject)",
      body_html: data["html"],
      body_text: data["text"],
      headers: data["headers"] || [],
      message_id: data["message_id"],
      received_at: parse_timestamp(data["created_at"])
    }

    case Messaging.receive_inbound_email(attrs) do
      {:ok, :duplicate} ->
        json(conn, %{status: "ok", note: "duplicate"})

      {:ok, _email} ->
        json(conn, %{status: "ok"})

      {:error, reason} ->
        Logger.error("Failed to process inbound email #{data["email_id"]}: #{inspect(reason)}")

        # Return 200 even on failure — non-2xx causes Resend to retry indefinitely.
        json(conn, %{status: "ok"})
    end
  end

  # Acknowledge but ignore non-email.received events; 200 prevents Resend retries.
  def handle(conn, %{"type" => type}) do
    Logger.debug("Ignoring Resend webhook event", type: type)
    json(conn, %{status: "ok"})
  end

  defp parse_timestamp(nil), do: DateTime.utc_now()

  defp parse_timestamp(timestamp_string) do
    case DateTime.from_iso8601(timestamp_string) do
      {:ok, dt, _offset} -> dt
      {:error, _} -> DateTime.utc_now()
    end
  end
end
