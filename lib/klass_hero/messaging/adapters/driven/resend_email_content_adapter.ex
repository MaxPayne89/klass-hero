defmodule KlassHero.Messaging.Adapters.Driven.ResendEmailContentAdapter do
  @moduledoc """
  Fetches inbound email content from Resend's receiving API.

  Implements ForFetchingEmailContent port using Req HTTP client.
  Endpoint: GET https://api.resend.com/emails/receiving/{id}
  """

  @behaviour KlassHero.Messaging.Domain.Ports.ForFetchingEmailContent

  use KlassHero.Shared.Tracing

  require Logger

  @base_url "https://api.resend.com"

  @impl true
  def fetch_content(resend_email_id) do
    span "resend_api.fetch_email_content" do
      set_attributes("http", service: "resend", operation: "fetch_email_content")

      extra_opts = Application.get_env(:klass_hero, :resend_req_options, [])
      req = Req.new([base_url: @base_url, auth: {:bearer, api_key()}] ++ extra_opts)

      case Req.get(req, url: "/emails/receiving/#{resend_email_id}") do
        {:ok, %Req.Response{status: 200, body: body}} ->
          set_attribute("http.status_code", 200)
          headers = normalize_headers(body["headers"])
          {:ok, %{html: body["html"], text: body["text"], headers: headers}}

        {:ok, %Req.Response{status: 404}} ->
          set_attribute("http.status_code", 404)
          {:error, :not_found}

        {:ok, %Req.Response{status: 429}} ->
          set_attribute("http.status_code", 429)
          {:error, :rate_limited}

        {:ok, %Req.Response{status: status}} when status >= 500 ->
          set_attribute("http.status_code", status)
          Logger.error("Resend API server error #{status} for email #{resend_email_id}")
          {:error, :server_error}

        {:ok, %Req.Response{status: status, body: body}} when status >= 400 ->
          set_attribute("http.status_code", status)

          Logger.error("Resend API client error #{status} for email #{resend_email_id}: #{inspect(body)}")

          {:error, {:client_error, status}}

        {:error, exception} ->
          Logger.error("Resend API request failed for email #{resend_email_id}: #{inspect(exception)}")

          {:error, :request_failed}
      end
    end
  end

  defp normalize_headers(nil), do: []
  defp normalize_headers(headers) when is_list(headers), do: headers

  defp normalize_headers(headers) when is_map(headers) do
    Enum.map(headers, fn {name, value} -> %{"name" => name, "value" => value} end)
  end

  defp api_key do
    # Test env uses Swoosh.Adapters.Test with no api_key; Req.Test stubs intercept before use.
    Application.get_env(:klass_hero, KlassHero.Mailer)[:api_key] || "unconfigured"
  end
end
