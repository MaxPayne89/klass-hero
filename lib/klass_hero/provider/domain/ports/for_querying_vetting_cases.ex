defmodule KlassHero.Provider.Domain.Ports.ForQueryingVettingCases do
  @moduledoc """
  Driven port for reading a Provider's `VettingCase`.
  """

  alias KlassHero.Provider.Domain.Models.VettingCase

  @doc "Fetches the vetting case for a provider, with its steps, or `{:error, :not_found}`."
  @callback get_by_provider(provider_id :: String.t()) :: {:ok, VettingCase.t()} | {:error, :not_found}
end
