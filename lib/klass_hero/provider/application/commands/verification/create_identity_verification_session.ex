defmodule KlassHero.Provider.Application.Commands.Verification.CreateIdentityVerificationSession do
  @moduledoc """
  Starts a Stripe Identity verification for a provider.

  Creates a hosted Verification Session via the identity port, records an `IdentityVerification`
  (status `:processing`) keyed by the Stripe session id, and submits the provider's `:identity`
  vetting step so the case reflects work in progress. Returns the hosted `redirect_url` the
  provider is sent to. The pass/fail outcome arrives later by webhook (ADR-0007).
  """

  alias KlassHero.Provider.Domain.Models.IdentityVerification
  alias KlassHero.Provider.Domain.Models.VettingCase

  @identity Application.compile_env!(:klass_hero, [:provider, :for_verifying_identity])
  @store Application.compile_env!(:klass_hero, [:provider, :for_storing_identity_verifications])
  @vetting_query Application.compile_env!(:klass_hero, [:provider, :for_querying_vetting_cases])
  @vetting_store Application.compile_env!(:klass_hero, [:provider, :for_storing_vetting_cases])

  @doc """
  Starts a session for `provider_id`, sending the provider back to `return_url` afterwards.

  Returns `{:ok, %{redirect_url: url}}`, or an `{:error, _}` from the identity provider, persistence,
  or the vetting case (e.g. `:no_identity_step` if the track has no Stripe identity step).
  """
  def execute(%{provider_id: provider_id, return_url: return_url}) do
    with {:ok, %{session_id: session_id, url: url}} <-
           @identity.create_session(%{provider_id: provider_id, return_url: return_url}),
         {:ok, _stored} <-
           @store.create(IdentityVerification.new(%{provider_id: provider_id, stripe_session_id: session_id})),
         {:ok, case_} <- @vetting_query.get_by_provider(provider_id),
         {:ok, key} <- fetch_identity_step_key(case_),
         {:ok, updated} <- VettingCase.submit_step(case_, key),
         {:ok, _} <- @vetting_store.update(updated) do
      {:ok, %{redirect_url: url}}
    end
  end

  defp fetch_identity_step_key(case_) do
    case VettingCase.step_key_for_identity(case_) do
      nil -> {:error, :no_identity_step}
      key -> {:ok, key}
    end
  end
end
