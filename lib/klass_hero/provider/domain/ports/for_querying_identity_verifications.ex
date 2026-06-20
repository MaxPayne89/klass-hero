defmodule KlassHero.Provider.Domain.Ports.ForQueryingIdentityVerifications do
  @moduledoc """
  Driven port for reading `IdentityVerification` evidence.
  """

  alias KlassHero.Provider.Domain.Models.IdentityVerification

  @typedoc "An identity verification paired with its provider's business name, for admin display."
  @type admin_result :: %{
          identity_verification: IdentityVerification.t(),
          provider_business_name: String.t()
        }

  @doc "Fetches the identity verification for a Stripe session id, or `{:error, :not_found}`."
  @callback get_by_session_id(session_id :: String.t()) ::
              {:ok, IdentityVerification.t()} | {:error, :not_found}

  @doc "Fetches the most recently created identity verification for a provider, or `{:error, :not_found}`."
  @callback get_latest_by_provider(provider_id :: String.t()) ::
              {:ok, IdentityVerification.t()} | {:error, :not_found}

  @doc "Lists all identity verifications with provider business names, newest first (admin)."
  @callback list_for_admin() :: {:ok, [admin_result()]}
end
