defmodule KlassHero.Messaging.Adapters.Driven.Provider.ProviderUserResolver do
  @moduledoc """
  Adapter for resolving a provider's owner user ID (via the Provider facade)
  for messaging permission checks.

  Delegates to the Provider facade to respect bounded context boundaries —
  Messaging is not allowed to query Provider schemas directly.
  """
  use KlassHero.Shared.Tracing

  @spec get_user_id_for_provider(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def get_user_id_for_provider(provider_id) do
    acl_span source: "messaging", target: "provider" do
      KlassHero.Provider.get_identity_id_for_provider(provider_id)
    end
  end
end
