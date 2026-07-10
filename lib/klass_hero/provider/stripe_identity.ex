defmodule KlassHero.Provider.StripeIdentity do
  @moduledoc """
  Creates Stripe Identity Verification Sessions via the Stripe REST API (raw `Req`).

  A single client module — not a behaviour. The session is configured with
  `type: "document"` so Stripe runs an ID-document + selfie check and returns a date of
  birth for the age gate (ADR-0009). The secret key and `Req` transport options are read
  lazily from config; tests inject a `Req.Test` plug via `:stripe_req_options`, so this
  exact code path runs in both test and production (no stub adapter).

  A missing secret key short-circuits with `{:error, :stripe_not_configured}` rather than
  raising, so the app boots before the feature is provisioned.
  """

  require Logger

  @base_url "https://api.stripe.com"

  @type result :: {:ok, %{session_id: String.t(), url: String.t()}} | {:error, error}
  @type error :: :stripe_not_configured | :server_error | :request_failed | {:client_error, integer()}

  @spec create_session(%{provider_id: String.t(), return_url: String.t()}) :: result
  def create_session(%{provider_id: provider_id, return_url: return_url}) do
    case secret_key() do
      nil -> {:error, :stripe_not_configured}
      key -> post_session(key, provider_id, return_url)
    end
  end

  defp post_session(key, provider_id, return_url) do
    extra_opts = Application.get_env(:klass_hero, :stripe_req_options, [])
    req = Req.new([base_url: @base_url, auth: {:bearer, key}] ++ extra_opts)

    form = [type: "document", return_url: return_url, "metadata[provider_id]": provider_id]

    case Req.post(req, url: "/v1/identity/verification_sessions", form: form) do
      {:ok, %Req.Response{status: 200, body: %{"id" => id, "url" => url}}} ->
        {:ok, %{session_id: id, url: url}}

      {:ok, %Req.Response{status: status}} when status >= 500 ->
        Logger.error("Stripe Identity server error #{status} creating session for #{provider_id}")
        {:error, :server_error}

      {:ok, %Req.Response{status: status, body: body}} when status >= 400 ->
        Logger.error("Stripe Identity client error #{status} for #{provider_id}: #{inspect(body)}")
        {:error, {:client_error, status}}

      {:error, exception} ->
        Logger.error("Stripe Identity request failed for #{provider_id}: #{inspect(exception)}")
        {:error, :request_failed}
    end
  end

  defp secret_key, do: Application.get_env(:klass_hero, :stripe, [])[:secret_key]
end
