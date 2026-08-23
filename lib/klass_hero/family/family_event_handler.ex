defmodule KlassHero.Family.FamilyEventHandler do
  @moduledoc """
  Integration event handler for the Family context.

  Listens to user-related events from the Accounts context and reacts accordingly:

  ## Subscribed Events

  - `:user_registered` - Creates parent profile if "parent" in intended_roles
  - `:user_confirmed` - Compensation path: creates parent profile if not yet created (idempotent)
  - `:user_anonymized` - Anonymizes Family-owned data (children, consents)
    and publishes `child_data_anonymized` per child for downstream contexts

  ## Error Handling

  Operations are handled gracefully with retry logic:
  - Duplicate identity → :ok (profile already exists)
  - Transient errors → Retry once, then log error
  """

  @behaviour KlassHero.Shared.ForHandlingEvents

  alias KlassHero.Family
  alias KlassHero.Shared.Adapters.Driven.Events.RetryHelpers

  @impl true
  def subscribed_events, do: [:user_registered, :user_confirmed, :user_anonymized]

  @impl true
  def handle_event(%{event_type: :user_anonymized, entity_id: user_id}) do
    anonymize_family_data_with_retry(user_id)
  end

  @impl true
  def handle_event(%{event_type: :user_registered, entity_id: user_id, payload: payload}) do
    intended_roles = Map.get(payload, :intended_roles, [])

    if "parent" in intended_roles do
      create_parent_profile_with_retry(user_id)
    else
      :ignore
    end
  end

  @impl true
  def handle_event(%{event_type: :user_confirmed, entity_id: user_id, payload: payload}) do
    intended_roles = Map.get(payload, :intended_roles, [])

    if "parent" in intended_roles do
      create_parent_profile_with_retry(user_id)
    else
      :ignore
    end
  end

  def handle_event(_event), do: :ignore

  defp create_parent_profile_with_retry(user_id) do
    operation = fn ->
      Family.create_parent_profile(%{identity_id: user_id})
    end

    context = %{
      operation_name: "create parent profile",
      aggregate_id: user_id,
      backoff_ms: 100
    }

    RetryHelpers.retry_and_normalize(operation, context)
  end

  defp anonymize_family_data_with_retry(user_id) do
    operation = fn ->
      Family.anonymize_data_for_user(user_id)
    end

    context = %{
      operation_name: "anonymize family data",
      aggregate_id: user_id,
      backoff_ms: 100
    }

    RetryHelpers.retry_and_normalize(operation, context)
  end
end
