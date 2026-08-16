defmodule KlassHero.Messaging.Adapters.Driven.Provider.ProviderStaffResolver do
  @moduledoc """
  Adapter for resolving provider-staff relationships in the Messaging context.

  Delegates to the Provider facade to respect bounded context boundaries —
  Messaging is not allowed to query Provider schemas directly.
  """
  use KlassHero.Shared.Tracing

  @spec active_staff_for_provider?(String.t(), String.t()) :: boolean()
  def active_staff_for_provider?(provider_id, user_id) do
    acl_span source: "messaging", target: "provider" do
      KlassHero.Provider.active_staff_for_provider?(provider_id, user_id)
    end
  end

  @doc """
  User IDs of the staff currently active on a program.

  Messaging mirrored this in `program_staff_participants` until #1321. The mirror
  had no projection, bootstrap or rebuild, so only an event could correct it —
  and three bugs (#1309, #1312, #1320) were drift between it and this source.
  """
  @spec list_active_staff_user_ids(String.t()) :: [String.t()]
  def list_active_staff_user_ids(program_id) do
    acl_span source: "messaging", target: "provider" do
      KlassHero.Provider.list_active_staff_user_ids_for_program(program_id)
    end
  end

  @doc """
  User IDs of everyone who has ever been staff at the provider.

  Only the render path wants this, and only for messages written before
  `messages.sender_role` existed (#1348). Employment *ever* is the closest available
  approximation of who was provider-side at send time; employment *now* — which is
  what `list_active_staff_user_ids/1` answers — is the question that rewrote history.
  """
  @spec list_staff_user_ids(String.t()) :: [String.t()]
  def list_staff_user_ids(provider_id) do
    acl_span source: "messaging", target: "provider" do
      KlassHero.Provider.list_staff_user_ids_for_provider(provider_id)
    end
  end
end
