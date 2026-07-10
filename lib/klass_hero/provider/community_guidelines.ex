defmodule KlassHero.Provider.CommunityGuidelines do
  @moduledoc """
  Policy for the Klass Hero Community Guidelines a provider agrees to as the final vetting step.
  Owns the current published `version`; the agreed-to version is recorded on each
  `SignedAgreement` so a material update can require providers to re-agree.

  The agreement *text* lives in the web layer (it is presentation); this module owns only the
  version policy and the re-agreement rule.

  ## Versioning is the legal contract

  Only bump `@current_version` on a material change (a new obligation, restriction, or liability);
  trivial edits keep the version so they never force re-agreement. Each version maps to an
  immutable PDF (`priv/static/downloads/Klass_Hero_Community_Standards_Agreement_v<version>.pdf`)
  that is never edited in place — the recorded `version` is worthless as evidence unless its
  document is reproducible verbatim.
  """

  alias KlassHero.Provider.SignedAgreement

  @current_version "1.0"

  @doc "The version of the Community Guidelines currently in force."
  @spec current_version() :: String.t()
  def current_version, do: @current_version

  @doc """
  Returns `true` when the provider's latest signed agreement still satisfies the current
  guidelines (no re-agreement required). `nil` (never signed) is not satisfied.

  Exact-match by design: every version in existence is one we deliberately want fresh consent for.
  """
  @spec agreement_satisfied?(SignedAgreement.t() | nil) :: boolean()
  def agreement_satisfied?(nil), do: false
  def agreement_satisfied?(%SignedAgreement{version: version}), do: version == current_version()
end
