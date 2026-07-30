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

  alias KlassHero.Provider.Adapters.Driving.Events.EventHandlers.VettingVerificationSync
  alias KlassHero.Provider.Vetting
  alias KlassHero.Provider.VettingCase
  alias KlassHero.Shared.Domain.Events.Event

  require Logger

  @spec handle(Event.t()) :: :ok | {:error, term()}
  def handle(%Event{event_type: :verification_document_approved, payload: payload}) do
    %{provider_id: provider_id, reviewer_id: reviewer_id, document_type: document_type, document_id: document_id} =
      payload

    with {:ok, case_} <- Vetting.get_case_for_provider(provider_id),
         step_key when not is_nil(step_key) <- VettingCase.step_key_for_document(case_, document_type),
         {:ok, updated} <- VettingCase.approve_step(case_, step_key, reviewer_id, document_id),
         {:ok, _} <- Vetting.save_case(updated) do
      VettingVerificationSync.verify_if_complete(updated, provider_id, reviewer_id)
      VettingVerificationSync.broadcast_updated(provider_id)
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

  def handle(%Event{event_type: :verification_document_rejected, payload: payload}) do
    %{provider_id: provider_id, reviewer_id: reviewer_id, document_type: document_type} = payload

    with {:ok, case_} <- Vetting.get_case_for_provider(provider_id),
         step_key when not is_nil(step_key) <- VettingCase.step_key_for_document(case_, document_type),
         {:ok, updated} <- VettingCase.reset_step(case_, step_key),
         {:ok, _} <- Vetting.save_case(updated) do
      VettingVerificationSync.maybe_unverify(provider_id, reviewer_id)
      VettingVerificationSync.broadcast_updated(provider_id)
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

  defp log_no_step(provider_id, document_type) do
    Logger.warning(
      "No vetting step consumes document_type=#{inspect(document_type)} for provider #{provider_id}; ignoring"
    )
  end
end
