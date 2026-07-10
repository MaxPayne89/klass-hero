defmodule KlassHero.Provider.Adapters.Driving.Events.EventHandlers.AdvanceVettingStepOnIdentityOutcome do
  @moduledoc """
  Domain event handler that bridges a Stripe Identity outcome to the Vetting Case — the
  identity counterpart of `AdvanceVettingStepOnDocumentReview`.

  A `:identity_verification_passed` event auto-approves the provider's `:identity` step
  (no human reviewer); if the case is then fully verified, the provider is verified with a
  `nil` (system) admin. A `:identity_verification_failed` event resets the identity step;
  if the provider was verified, it is unverified.

  Registered on the Provider DomainEventBus for:
  - `:identity_verification_passed`
  - `:identity_verification_failed`
  """

  alias KlassHero.Provider.Adapters.Driving.Events.EventHandlers.VettingVerificationSync
  alias KlassHero.Provider.Vetting
  alias KlassHero.Provider.VettingCase
  alias KlassHero.Shared.Domain.Events.DomainEvent

  require Logger

  @spec handle(DomainEvent.t()) :: :ok | {:error, term()}
  def handle(%DomainEvent{event_type: :identity_verification_passed, payload: payload}) do
    %{provider_id: provider_id, identity_verification_id: evidence_ref} = payload

    with {:ok, case_} <- Vetting.get_case_for_provider(provider_id),
         step_key when not is_nil(step_key) <- VettingCase.step_key_for_identity(case_),
         {:ok, updated} <- VettingCase.auto_approve_step(case_, step_key, evidence_ref),
         {:ok, _} <- Vetting.save_case(updated) do
      if VettingCase.verified?(updated), do: VettingVerificationSync.verify(provider_id, nil)
      VettingVerificationSync.broadcast_updated(provider_id)
      :ok
    else
      nil ->
        log_no_identity_step(provider_id)
        :ok

      {:error, :not_found} ->
        :ok

      {:error, reason} ->
        {:error, {:vetting_advance_failed, reason}}
    end
  end

  def handle(%DomainEvent{event_type: :identity_verification_failed, payload: payload}) do
    %{provider_id: provider_id} = payload

    with {:ok, case_} <- Vetting.get_case_for_provider(provider_id),
         step_key when not is_nil(step_key) <- VettingCase.step_key_for_identity(case_),
         {:ok, updated} <- VettingCase.reset_step(case_, step_key),
         {:ok, _} <- Vetting.save_case(updated) do
      VettingVerificationSync.maybe_unverify(provider_id, nil)
      VettingVerificationSync.broadcast_updated(provider_id)
      :ok
    else
      nil ->
        log_no_identity_step(provider_id)
        :ok

      {:error, :not_found} ->
        :ok

      {:error, reason} ->
        {:error, {:vetting_reset_failed, reason}}
    end
  end

  defp log_no_identity_step(provider_id) do
    Logger.warning("No Stripe Identity step in track for provider #{provider_id}; ignoring identity outcome")
  end
end
