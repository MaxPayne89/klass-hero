defmodule KlassHero.Provider.Adapters.Driving.Events.EventHandlers.AdvanceVettingStepOnDocumentReview do
  @moduledoc """
  Domain event handler that bridges document review to the Vetting Case.

  Replaces the binary `all_approved?` engine. When a `VerificationDocument` is approved, the
  matching document step on the provider's `VettingCase` is approved; if the case is then fully
  verified, the provider is verified via the unchanged `VerifyProvider` command (which emits the
  `provider_verified` integration event). When a document is rejected, its step is reset; if the
  provider was verified, `UnverifyProvider` runs.

  Registered on the Provider DomainEventBus for:
  - :verification_document_approved
  - :verification_document_rejected
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
  def handle(%DomainEvent{event_type: :verification_document_approved, payload: payload}) do
    %{provider_id: provider_id, reviewer_id: reviewer_id, document_type: document_type, document_id: document_id} =
      payload

    with {:ok, case_} <- @vetting_query.get_by_provider(provider_id),
         step_key when not is_nil(step_key) <- VettingCase.step_key_for_document(case_, document_type),
         {:ok, updated} <- VettingCase.approve_step(case_, step_key, reviewer_id, document_id),
         {:ok, _} <- @vetting_store.update(updated) do
      if VettingCase.verified?(updated), do: verify(provider_id, reviewer_id)
      :ok
    else
      nil -> :ok
      {:error, :not_found} -> :ok
      {:error, reason} -> {:error, {:vetting_advance_failed, reason}}
    end
  end

  def handle(%DomainEvent{event_type: :verification_document_rejected, payload: payload}) do
    %{provider_id: provider_id, reviewer_id: reviewer_id, document_type: document_type} = payload

    with {:ok, case_} <- @vetting_query.get_by_provider(provider_id),
         step_key when not is_nil(step_key) <- VettingCase.step_key_for_document(case_, document_type),
         {:ok, updated} <- VettingCase.reset_step(case_, step_key),
         {:ok, _} <- @vetting_store.update(updated) do
      maybe_unverify(provider_id, reviewer_id)
      :ok
    else
      nil -> :ok
      {:error, :not_found} -> :ok
      {:error, reason} -> {:error, {:vetting_reset_failed, reason}}
    end
  end

  defp verify(provider_id, reviewer_id) do
    case VerifyProvider.execute(%{provider_id: provider_id, admin_id: reviewer_id}) do
      {:ok, _} -> :ok
      {:error, reason} -> Logger.warning("Auto-verify failed for provider #{provider_id}: #{inspect(reason)}")
    end
  end

  defp maybe_unverify(provider_id, reviewer_id) do
    with {:ok, profile} <- @profile_query.get(provider_id),
         true <- profile.verified do
      case UnverifyProvider.execute(%{provider_id: provider_id, admin_id: reviewer_id}) do
        {:ok, _} -> :ok
        {:error, reason} -> Logger.warning("Auto-unverify failed for provider #{provider_id}: #{inspect(reason)}")
      end
    end
  end
end
