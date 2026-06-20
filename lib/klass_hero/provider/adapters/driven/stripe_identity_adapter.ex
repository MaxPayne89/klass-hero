defmodule KlassHero.Provider.Adapters.Driven.StripeIdentityAdapter do
  @moduledoc """
  Creates Stripe Identity Verification Sessions via the Stripe REST API (raw `Req`).

  Implements `ForVerifyingIdentity`. The session is configured with `type: "document"` so Stripe
  runs an ID-document + selfie check and returns a date of birth for the age gate (ADR-0007). The
  secret key and `Req` transport options are read from config; tests inject a `Req.Test` plug via
  `:stripe_req_options`, so this exact code path runs in both test and production.
  """

  @behaviour KlassHero.Provider.Domain.Ports.ForVerifyingIdentity

  use KlassHero.Shared.Interaction

  require Logger

  @base_url "https://api.stripe.com"

  @impl true
  def create_session(%{provider_id: provider_id, return_url: return_url}) do
    http_interaction operation: :create_verification_session, service: "stripe" do
      case secret_key() do
        nil ->
          {:error, :stripe_not_configured}

        key ->
          create_session(key, provider_id, return_url)
      end
    end
  end

  defp create_session(key, provider_id, return_url) do
    extra_opts = Application.get_env(:klass_hero, :stripe_req_options, [])
    req = Req.new([base_url: @base_url, auth: {:bearer, key}] ++ extra_opts)

    form = [
      type: "document",
      return_url: return_url,
      "metadata[provider_id]": provider_id
    ]

    case Req.post(req, url: "/v1/identity/verification_sessions", form: form) do
      {:ok, %Req.Response{status: 200, body: %{"id" => id, "url" => url}}} ->
        set_attribute("http.status_code", 200)
        {:ok, %{session_id: id, url: url}}

      {:ok, %Req.Response{status: status}} when status >= 500 ->
        set_attribute("http.status_code", status)
        Logger.error("Stripe Identity server error #{status} creating session for #{provider_id}")
        {:error, :server_error}

      {:ok, %Req.Response{status: status, body: body}} when status >= 400 ->
        set_attribute("http.status_code", status)
        Logger.error("Stripe Identity client error #{status} for #{provider_id}: #{inspect(body)}")
        {:error, {:client_error, status}}

      {:error, exception} ->
        Logger.error("Stripe Identity request failed for #{provider_id}: #{inspect(exception)}")
        {:error, :request_failed}
    end
  end

  defp secret_key, do: Application.get_env(:klass_hero, :stripe, [])[:secret_key]
end
