defmodule KlassHero.Provider.Adapters.Driving.Events.EventHandlers.AdvanceVettingStepOnDocumentReview do
  @moduledoc """
  Domain event handler that bridges document review to the Vetting Case.

  Replaces the binary `all_approved?` engine. When a `VerificationDocument` is
  approved, the matching document step on the provider's `VettingCase` is approved;
  if the case is then fully verified, the provider is verified via the unchanged
  `Provider.verify_provider/2` path (which emits the `provider_verified` integration
  event). When a document is rejected, its step is reset; if the provider was
  verified, it is unverified.

  Registered on the Provider DomainEventBus for:
  - `:verification_document_approved`
  - `:verification_document_rejected`
  """

  alias KlassHero.Provider
  alias KlassHero.Provider.Vetting
  alias KlassHero.Provider.VettingCase
  alias KlassHero.Shared.Domain.Events.DomainEvent

  require Logger

  @spec handle(DomainEvent.t()) :: :ok | {:error, term()}
  def handle(%DomainEvent{event_type: :verification_document_approved, payload: payload}) do
    %{provider_id: provider_id, reviewer_id: reviewer_id, document_type: document_type, document_id: document_id} =
      payload

    with {:ok, case_} <- Vetting.get_case_for_provider(provider_id),
         step_key when not is_nil(step_key) <- VettingCase.step_key_for_document(case_, document_type),
         {:ok, updated} <- VettingCase.approve_step(case_, step_key, reviewer_id, document_id),
         {:ok, _} <- Vetting.save_case(updated) do
      if VettingCase.verified?(updated), do: verify(provider_id, reviewer_id)
      :ok
    else
      nil ->
        log_no_step(provider_id, document_type)
        :ok

      {:error, :not_found} ->
        :ok

      {:error, reason} ->
        {:error, {:vetting_advance_failed, reason}}
    end
  end

  def handle(%DomainEvent{event_type: :verification_document_rejected, payload: payload}) do
    %{provider_id: provider_id, reviewer_id: reviewer_id, document_type: document_type} = payload

    with {:ok, case_} <- Vetting.get_case_for_provider(provider_id),
         step_key when not is_nil(step_key) <- VettingCase.step_key_for_document(case_, document_type),
         {:ok, updated} <- VettingCase.reset_step(case_, step_key),
         {:ok, _} <- Vetting.save_case(updated) do
      maybe_unverify(provider_id, reviewer_id)
      :ok
    else
      nil ->
        log_no_step(provider_id, document_type)
        :ok

      {:error, :not_found} ->
        :ok

      {:error, reason} ->
        {:error, {:vetting_reset_failed, reason}}
    end
  end

  defp verify(provider_id, reviewer_id) do
    case Provider.verify_provider(provider_id, reviewer_id) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("Auto-verify failed for provider #{provider_id}: #{inspect(reason)}")
        :ok
    end
  end

  # Only unverify a currently-verified provider, so a document rejection on an
  # unverified provider never emits a spurious `provider_unverified` event.
  defp maybe_unverify(provider_id, reviewer_id) do
    case Provider.get_provider_profile(provider_id) do
      {:ok, %{verified: true}} -> Provider.unverify_provider(provider_id, reviewer_id)
      _ -> :ok
    end

    :ok
  end

  defp log_no_step(provider_id, document_type) do
    Logger.warning(
      "No vetting step consumes document_type=#{inspect(document_type)} for provider #{provider_id}; ignoring"
    )
  end
end
