defmodule KlassHero.Provider.Adapters.Driving.Events.EventHandlers.VettingVerificationSync do
  @moduledoc """
  Shared bridge from a fully-verified (or newly-unverified) Vetting Case to the
  published `ProviderProfile.verified` fact. Used by both step-advance handlers
  (document review and Stripe Identity outcome) so the verify/unverify path — and the
  frozen `provider_verified`/`provider_unverified` integration events it emits — is
  written once.

  `reviewer_id` is the admin id for document approvals, or `nil` for system-driven
  verification (the Stripe Identity webhook).
  """

  alias KlassHero.Provider
  alias KlassHero.Provider.VettingCase

  require Logger

  @doc """
  Fire-and-forget nudge to any mounted `VerificationLive` for this provider to re-fetch.
  Provider-scoped topic; carries no payload (the DB row is the source of truth). Broadcast
  last, after the case is saved — never let a PubSub hiccup break the engine advance.
  """
  @spec broadcast_updated(String.t()) :: :ok
  def broadcast_updated(provider_id) do
    Phoenix.PubSub.broadcast(
      KlassHero.PubSub,
      "provider:#{provider_id}:verification_updated",
      :verification_updated
    )

    :ok
  end

  @doc """
  Verifies the provider iff the case is now fully approved; otherwise a no-op. Lets each step
  handler hand over the recomputed case without repeating the `verified?` gate at every call site.
  """
  @spec verify_if_complete(VettingCase.t(), String.t(), String.t() | nil) :: :ok
  def verify_if_complete(%VettingCase{} = case_, provider_id, reviewer_id) do
    if VettingCase.verified?(case_), do: verify(provider_id, reviewer_id), else: :ok
  end

  @doc "Verifies the provider; logs and swallows a verify failure (the step is already saved)."
  @spec verify(String.t(), String.t() | nil) :: :ok
  def verify(provider_id, reviewer_id) do
    case Provider.verify_provider(provider_id, reviewer_id) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("Auto-verify failed for provider #{provider_id}: #{inspect(reason)}")
        :ok
    end
  end

  @doc """
  Unverifies the provider only if currently verified, so a rejection on an unverified
  provider never emits a spurious `provider_unverified` event.
  """
  @spec maybe_unverify(String.t(), String.t() | nil) :: :ok
  def maybe_unverify(provider_id, reviewer_id) do
    case Provider.get_provider_profile(provider_id) do
      {:ok, %{verified: true}} -> Provider.unverify_provider(provider_id, reviewer_id)
      _ -> :ok
    end

    :ok
  end
end
