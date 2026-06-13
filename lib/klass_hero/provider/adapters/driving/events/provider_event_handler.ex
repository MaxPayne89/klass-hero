defmodule KlassHero.Provider.Adapters.Driving.Events.ProviderEventHandler do
  @moduledoc """
  Integration event handler for the Provider context.

  Listens to user-related events from the Accounts context and reacts accordingly:

  ## Subscribed Events

  - `:user_registered` - Creates provider profile if "provider" in intended_roles
  - `:user_confirmed` - Compensation path: creates provider profile if not yet created (idempotent)
  - `:user_anonymized` - No-op for Provider context (provider profiles have no PII
    beyond business_name which is retained for audit purposes)

  ## Error Handling

  Operations are handled gracefully with retry logic:
  - Duplicate identity → :ok (profile already exists)
  - Transient errors → Retry once, then log error
  """

  @behaviour KlassHero.Shared.Domain.Ports.Driving.ForHandlingEvents

  alias KlassHero.Provider
  alias KlassHero.Shared.Adapters.Driven.Events.RetryHelpers

  @impl true
  def subscribed_events, do: [:user_registered, :user_confirmed, :user_anonymized]

  @impl true
  def handle_event(%{event_type: :user_anonymized, entity_id: _user_id}), do: :ok

  @impl true
  def handle_event(%{event_type: event_type, entity_id: user_id, payload: payload})
      when event_type in [:user_registered, :user_confirmed] do
    # Guard: staff-only registrations carry [:staff] (ADR-0005) and are excluded here — no special-casing needed.
    intended_roles = Map.get(payload, :intended_roles, [])

    if "provider" in intended_roles do
      user_id
      |> build_attrs_from_payload(payload)
      |> create_provider_profile_with_retry(user_id)
    else
      :ignore
    end
  end

  def handle_event(_event), do: :ignore

  defp build_attrs_from_payload(user_id, payload) do
    %{
      identity_id: user_id,
      business_name: Map.get(payload, :name, ""),
      business_owner_email: Map.get(payload, :email)
    }
  end

  defp create_provider_profile_with_retry(attrs, user_id) do
    operation = fn -> Provider.create_provider_profile(attrs) end

    context = %{
      operation_name: "create provider profile",
      aggregate_id: user_id,
      backoff_ms: 100
    }

    RetryHelpers.retry_and_normalize(operation, context)
  end
end
