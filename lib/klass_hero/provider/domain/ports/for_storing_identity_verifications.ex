defmodule KlassHero.Provider.Domain.Ports.ForStoringIdentityVerifications do
  @moduledoc """
  Driven port for persisting `IdentityVerification` evidence (one row per Stripe session).
  """

  alias KlassHero.Provider.Domain.Models.IdentityVerification

  @doc "Persists a new identity verification record."
  @callback create(IdentityVerification.t()) :: {:ok, IdentityVerification.t()} | {:error, term()}

  @doc "Persists changes to an identity verification (status/outcome transitions)."
  @callback update(IdentityVerification.t()) :: {:ok, IdentityVerification.t()} | {:error, term()}
end
