defmodule KlassHero.Provider.Adapters.Driving.Events.EventHandlers.CheckProviderVerificationStatus do
  @moduledoc """
  Domain event handler that bridges document approval to provider verification.

  When a verification document is approved, checks if ALL the provider's documents
  are now approved. If so, auto-verifies the provider via VerifyProvider use case.

  When a document is rejected, checks if the provider was previously verified.
  If so, auto-unverifies via UnverifyProvider use case.

  Registered on the Provider DomainEventBus for:
  - :verification_document_approved
  - :verification_document_rejected
  """

  alias KlassHero.Provider.Application.Commands.Providers.UnverifyProvider
  alias KlassHero.Provider.Application.Commands.Providers.VerifyProvider
  alias KlassHero.Shared.Domain.Events.DomainEvent

  require Logger

  @doc_repository Application.compile_env!(:klass_hero, [
                    :provider,
                    :for_querying_verification_documents
                  ])

  @profile_repository Application.compile_env!(:klass_hero, [
                        :provider,
                        :for_querying_provider_profiles
                      ])

  @doc """
  Handles verification document domain events.

  For :verification_document_approved — checks all docs, verifies provider if all approved.
  For :verification_document_rejected — unverifies provider if currently verified.
  """
  @spec handle(DomainEvent.t()) :: :ok | {:error, term()}
  def handle(%DomainEvent{event_type: :verification_document_approved, payload: payload}) do
    %{provider_id: provider_id, reviewer_id: reviewer_id} = payload

    with {:ok, docs} <- @doc_repository.get_by_provider(provider_id),
         true <- all_approved?(docs) do
      case VerifyProvider.execute(%{provider_id: provider_id, admin_id: reviewer_id}) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning("Auto-verify failed for provider #{provider_id}: #{inspect(reason)}")
          :ok
      end
    else
      false -> :ok
      {:error, reason} -> {:error, {:verification_check_failed, reason}}
    end
  end

  def handle(%DomainEvent{event_type: :verification_document_rejected, payload: payload}) do
    %{provider_id: provider_id, reviewer_id: reviewer_id} = payload

    with {:ok, profile} <- @profile_repository.get(provider_id),
         true <- profile.verified do
      case UnverifyProvider.execute(%{provider_id: provider_id, admin_id: reviewer_id}) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning("Auto-unverify failed for provider #{provider_id}: #{inspect(reason)}")
          :ok
      end
    else
      false -> :ok
      {:error, reason} -> {:error, {:unverification_check_failed, reason}}
    end
  end

  # Verification requires ALL documents approved and at least one present.
  defp all_approved?([]), do: false
  defp all_approved?(docs), do: Enum.all?(docs, &(&1.status == :approved))
end
