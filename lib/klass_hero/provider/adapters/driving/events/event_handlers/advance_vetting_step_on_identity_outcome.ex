defmodule KlassHero.Provider.Adapters.Driving.Events.EventHandlers.AdvanceVettingStepOnIdentityOutcome do
  @moduledoc """
  Domain event handler that bridges a Stripe Identity outcome to the Vetting Case — the identity
  counterpart of `AdvanceVettingStepOnDocumentReview`, advancing the case the same way.

  A `:identity_verification_passed` event auto-approves the provider's `:identity` step (no human
  reviewer); if the case is then fully verified, the provider is verified via `VerifyProvider` with
  a `nil` (system) admin. A `:identity_verification_failed` event resets the identity step; if the
  provider was verified, `UnverifyProvider` runs.

  Registered on the Provider DomainEventBus for:
  - :identity_verification_passed
  - :identity_verification_failed
  """

  alias KlassHero.Provider.Application.Commands.Providers.UnverifyProvider
  alias KlassHero.Provider.Application.Commands.Providers.VerifyProvider
  alias KlassHero.Provider.Domain.Models.VettingCase
  alias KlassHero.Shared.Domain.Events.DomainEvent

  require Logger

  @vetting_query Application.compile_env!(:klass_hero, [:provider, :for_querying_vetting_cases])
  @vetting_store Application.compile_env!(:klass_hero, [:provider, :for_storing_vetting_cases])
  @profile_query Application.compile_env!(:klass_hero, [:provider, :for_querying_provider_profiles])

  @spec handle(DomainEvent.t()) :: :ok | {:error, term()}
  def handle(%DomainEvent{event_type: :identity_verification_passed, payload: payload}) do
    %{provider_id: provider_id, identity_verification_id: evidence_ref} = payload

    with {:ok, case_} <- @vetting_query.get_by_provider(provider_id),
         step_key when not is_nil(step_key) <- VettingCase.step_key_for_identity(case_),
         {:ok, updated} <- VettingCase.auto_approve_step(case_, step_key, evidence_ref),
         {:ok, _} <- @vetting_store.update(updated) do
      if VettingCase.verified?(updated), do: verify(provider_id)
      :ok
    else
      nil -> :ok
      {:error, :not_found} -> :ok
      {:error, reason} -> {:error, {:vetting_advance_failed, reason}}
    end
  end

  def handle(%DomainEvent{event_type: :identity_verification_failed, payload: payload}) do
    %{provider_id: provider_id} = payload

    with {:ok, case_} <- @vetting_query.get_by_provider(provider_id),
         step_key when not is_nil(step_key) <- VettingCase.step_key_for_identity(case_),
         {:ok, updated} <- VettingCase.reset_step(case_, step_key),
         {:ok, _} <- @vetting_store.update(updated) do
      maybe_unverify(provider_id)
      :ok
    else
      nil -> :ok
      {:error, :not_found} -> :ok
      {:error, reason} -> {:error, {:vetting_reset_failed, reason}}
    end
  end

  defp verify(provider_id) do
    case VerifyProvider.execute(%{provider_id: provider_id, admin_id: nil}) do
      {:ok, _} -> :ok
      {:error, reason} -> Logger.warning("Identity auto-verify failed for provider #{provider_id}: #{inspect(reason)}")
    end
  end

  defp maybe_unverify(provider_id) do
    with {:ok, profile} <- @profile_query.get(provider_id),
         true <- profile.verified do
      case UnverifyProvider.execute(%{provider_id: provider_id, admin_id: nil}) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning("Identity auto-unverify failed for provider #{provider_id}: #{inspect(reason)}")
      end
    end
  end
end
