defmodule KlassHero.Provider.SubmitSignedAgreement do
  @moduledoc """
  Records a provider's signature on a versioned `SignedAgreement` — the Community Standards
  Agreement (`:community_agreement`, B4) or the Staff Compliance Declaration (`:staff_attestation`,
  B5) — and advances the matching vetting step.

  Persists a `SignedAgreement` (append-only consent evidence) at the version in force for its
  `kind`, then **auto-approves** the step — there is no admin review. When that was the last
  outstanding step, the provider is verified via the shared `VettingVerificationSync`, which emits
  the frozen `provider_verified` integration event.

  Unlike the document- and identity-review paths, signing has no external actor and no admin queue,
  so it advances the step *inline and synchronously* — there is no signed domain event and no event
  handler. Writes are sequential, not one transaction: `VettingCase.auto_approve_step/3` is
  idempotent, so a failure after the agreement is persisted is recovered by re-submitting (a fresh
  append-only agreement plus a no-op re-approval).

  The signer and the snapshotted `entity_type` both come from the provider: a business agreement is
  signed by the responsible person and stamped `:business`; an individual signs as themselves. The
  version comes from the engine (`Vetting.current_signed_agreement_version/1`), so this command
  stays ignorant of which concrete policy module owns each kind.
  """

  alias KlassHero.Provider
  alias KlassHero.Provider.Adapters.Driving.Events.EventHandlers.VettingVerificationSync
  alias KlassHero.Provider.ProviderProfile
  alias KlassHero.Provider.SignedAgreement
  alias KlassHero.Provider.Vetting
  alias KlassHero.Provider.VettingCase
  alias KlassHero.Repo

  @doc """
  Signs the agreement of `kind` for `provider_id` under `signed_by_name`.

  Returns `{:ok, signed_agreement}`, `{:error, errors}` for an invalid submission (e.g. a blank
  signer name), `{:error, :missing_responsible_person}` when a business has no responsible person
  on record, or an `{:error, _}` from persistence or the vetting case (e.g.
  `:no_signed_agreement_step` when the track has no step of that kind).
  """
  @spec execute(%{
          kind: SignedAgreement.kind(),
          provider_id: String.t(),
          signed_by_name: String.t()
        }) :: {:ok, SignedAgreement.t()} | {:error, term()}
  def execute(%{kind: kind, provider_id: provider_id, signed_by_name: signed_by_name}) do
    # The signer and the snapshotted entity_type both come from the provider: a business agreement
    # is signed by the responsible person and stamped :business; an individual signs as themselves.
    # Resolve the agreement and its target step before persisting any consent evidence, so a
    # provider whose track has no step of this kind never leaves an orphan SignedAgreement behind.
    with {:ok, profile} <- Provider.get_provider_profile(provider_id),
         {:ok, signer_name} <- resolve_signer(profile, signed_by_name),
         {:ok, agreement} <-
           SignedAgreement.new(%{
             provider_id: profile.id,
             kind: kind,
             signed_by_name: signer_name,
             entity_type: profile.entity_type,
             version: Vetting.current_signed_agreement_version(kind)
           }),
         {:ok, case_} <- Vetting.get_case_for_provider(provider_id),
         {:ok, key} <- fetch_agreement_step_key(case_, kind),
         {:ok, stored} <- insert_agreement(agreement),
         {:ok, updated} <- VettingCase.auto_approve_step(case_, key, stored.id),
         {:ok, saved} <- Vetting.save_case(updated) do
      VettingVerificationSync.verify_if_complete(saved, provider_id, nil)
      # Broadcast last: a PubSub hiccup must never undo an already-saved advance.
      VettingVerificationSync.broadcast_updated(provider_id)
      {:ok, stored}
    end
  end

  # Resolves who signs. An individual signs as themselves (`fallback_name`, the logged-in user); a
  # business agreement is signed by the named, legally-accountable responsible person captured in B1
  # — never the logged-in user — and fails closed if no responsible person is on record. The
  # business signer rule itself lives on the entity (`ProviderProfile.agreement_signer_name/1`),
  # shared with the read-path display in the LiveView.
  @spec resolve_signer(ProviderProfile.t(), String.t()) ::
          {:ok, String.t()} | {:error, :missing_responsible_person}
  defp resolve_signer(%ProviderProfile{entity_type: :business} = profile, _fallback_name) do
    case ProviderProfile.agreement_signer_name(profile) do
      nil -> {:error, :missing_responsible_person}
      name -> {:ok, name}
    end
  end

  defp resolve_signer(%ProviderProfile{} = _profile, fallback_name), do: {:ok, fallback_name}

  defp fetch_agreement_step_key(case_, kind) do
    case VettingCase.step_key_for_signed_agreement(case_, kind) do
      nil -> {:error, :no_signed_agreement_step}
      key -> {:ok, key}
    end
  end

  defp insert_agreement(%SignedAgreement{} = agreement) do
    attrs = Map.take(agreement, ~w(id provider_id kind entity_type signed_by_name signed_at version)a)

    %SignedAgreement{}
    |> SignedAgreement.changeset(attrs)
    |> Repo.insert()
  end
end
