defmodule KlassHero.Provider.StaffAttestationPolicy do
  @moduledoc """
  Policy for the Provider Child Safety Compliance Declaration a business's responsible person
  signs as the final business-track vetting step (B5). Mirrors `CommunityGuidelines`: owns the
  current published `version`; the signed version is recorded on each `SignedAgreement` so a
  material update can require re-attestation.

  The declaration *text* lives in the web layer (it is presentation); this module owns only the
  version policy and the re-attestation rule.

  ## Provisional until legal sign-off

  The declaration is legally binding (§ 72a SGB VIII, § 278/§ 823 BGB, a Vertragsstrafe under
  § 339 BGB whose amount is still TBD) and **must be reviewed by a German-qualified lawyer before
  go-live**. Until then the version is `"1.0-provisional"`. Because re-attestation is triggered by
  a version change (exact-match below), shipping the lawyer-approved `"1.0"` later automatically
  forces every provisional signer to re-attest — the legal gate enforces itself.

  Re-attestation is *also* triggered, for free, when the responsible person changes: the
  `staff_attestation` step declares `requires: [:responsible_person_identity]`, so
  `set_responsible_person/3`'s reset cascade clears it (ADR-0010).
  """

  alias KlassHero.Provider.SignedAgreement

  @current_version "1.0-provisional"

  @doc "The version of the Staff Compliance Declaration currently in force."
  @spec current_version() :: String.t()
  def current_version, do: @current_version

  @doc """
  Returns `true` when the provider's latest staff attestation still satisfies the current
  declaration (no re-attestation required). `nil` (never signed) is not satisfied.

  Exact-match by design: every version in existence is one we deliberately want fresh consent for.
  """
  @spec attestation_satisfied?(SignedAgreement.t() | nil) :: boolean()
  def attestation_satisfied?(nil), do: false
  def attestation_satisfied?(%SignedAgreement{version: version}), do: version == current_version()
end
