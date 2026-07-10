defmodule KlassHero.Provider.SubmitCommunityAgreement do
  @moduledoc """
  Records a provider's agreement to the current Community Guidelines and advances their vetting.

  Persists a `SignedAgreement` (append-only consent evidence) at the version in force, then
  **auto-approves** the `:community_agreement` step — there is no admin review. When that was the
  last outstanding step, the provider is verified via the shared `VettingVerificationSync`, which
  emits the frozen `provider_verified` integration event.

  Unlike the document- and identity-review paths, signing has no external actor and no admin
  queue, so it advances the step *inline and synchronously* — there is no
  `:community_agreement_signed` domain event and no event handler. Writes are sequential, not one
  transaction: `VettingCase.auto_approve_step/3` is idempotent, so a failure after the agreement is
  persisted is recovered by re-submitting (a fresh append-only agreement plus a no-op re-approval).
  """

  alias KlassHero.Provider.Adapters.Driving.Events.EventHandlers.VettingVerificationSync
  alias KlassHero.Provider.CommunityGuidelines
  alias KlassHero.Provider.SignedAgreement
  alias KlassHero.Provider.Vetting
  alias KlassHero.Provider.VettingCase
  alias KlassHero.Repo

  @doc """
  Signs the Community Standards Agreement for `provider_id` under `signed_by_name`.

  Returns `{:ok, signed_agreement}`, `{:error, errors}` for an invalid submission (e.g. a blank
  signer name), or an `{:error, _}` from persistence or the vetting case (e.g.
  `:no_community_agreement_step` when the track has none).
  """
  @spec execute(%{provider_id: String.t(), signed_by_name: String.t()}) ::
          {:ok, SignedAgreement.t()} | {:error, term()}
  def execute(%{provider_id: provider_id, signed_by_name: signed_by_name}) do
    attrs = %{
      provider_id: provider_id,
      signed_by_name: signed_by_name,
      version: CommunityGuidelines.current_version()
    }

    # Resolve the agreement and its target step before persisting any consent evidence, so a
    # provider whose track has no agreement step never leaves an orphan SignedAgreement behind.
    with {:ok, agreement} <- SignedAgreement.new(attrs),
         {:ok, case_} <- Vetting.get_case_for_provider(provider_id),
         {:ok, key} <- fetch_agreement_step_key(case_),
         {:ok, stored} <- insert_agreement(agreement),
         {:ok, updated} <- VettingCase.auto_approve_step(case_, key, stored.id),
         {:ok, saved} <- Vetting.save_case(updated) do
      VettingVerificationSync.verify_if_complete(saved, provider_id, nil)
      # Broadcast last: a PubSub hiccup must never undo an already-saved advance.
      VettingVerificationSync.broadcast_updated(provider_id)
      {:ok, stored}
    end
  end

  defp fetch_agreement_step_key(case_) do
    case VettingCase.step_key_for_signed_agreement(case_, :community_agreement) do
      nil -> {:error, :no_community_agreement_step}
      key -> {:ok, key}
    end
  end

  defp insert_agreement(%SignedAgreement{} = agreement) do
    attrs = Map.take(agreement, ~w(id provider_id kind signed_by_name signed_at version)a)

    %SignedAgreement{}
    |> SignedAgreement.changeset(attrs)
    |> Repo.insert()
  end
end
