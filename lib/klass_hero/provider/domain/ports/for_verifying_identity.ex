defmodule KlassHero.Provider.Domain.Ports.ForVerifyingIdentity do
  @moduledoc """
  Driven port for starting an identity verification with the external provider (Stripe Identity).

  The application calls this outward to create a hosted Verification Session; the actual outcome
  arrives asynchronously by webhook (ADR-0007), never through this call.
  """

  @doc """
  Creates a Verification Session for the given provider, returning the Stripe session id and the
  hosted `url` the provider is redirected to. `return_url` is where Stripe sends the provider back.
  """
  @callback create_session(%{provider_id: String.t(), return_url: String.t()}) ::
              {:ok, %{session_id: String.t(), url: String.t()}} | {:error, term()}
end
