defmodule KlassHero.Provider.Domain.Ports.ForStoringVettingCases do
  @moduledoc """
  Driven port for persisting a `VettingCase` and its `VerificationStep`s.
  """

  alias KlassHero.Provider.Domain.Models.VettingCase

  @doc "Persists a new vetting case together with all of its steps."
  @callback create(VettingCase.t()) :: {:ok, VettingCase.t()} | {:error, term()}

  @doc "Persists changes to a vetting case (lifecycle) and its steps' statuses."
  @callback update(VettingCase.t()) :: {:ok, VettingCase.t()} | {:error, term()}
end
