defmodule KlassHero.Provider.Domain.Ports.ForQueryingIdentityVerifications do
  @moduledoc """
  Driven port for reading `IdentityVerification` evidence.
  """

  alias KlassHero.Provider.Domain.Models.IdentityVerification

  @doc "Fetches the identity verification for a Stripe session id, or `{:error, :not_found}`."
  @callback get_by_session_id(session_id :: String.t()) ::
              {:ok, IdentityVerification.t()} | {:error, :not_found}

  @doc "Fetches the most recently created identity verification for a provider, or `{:error, :not_found}`."
  @callback get_latest_by_provider(provider_id :: String.t()) ::
              {:ok, IdentityVerification.t()} | {:error, :not_found}
end
