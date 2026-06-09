defmodule KlassHero.Accounts.Adapters.Driving.Events.StaffInvitationHandler do
  @moduledoc """
  Integration event handler for `:staff_member_invited` events from Provider context.

  Handles three paths:
  - New user: sends invitation email, emits :staff_invitation_sent
  - Existing user: sends notification, emits :staff_user_registered immediately
  - Email failure: emits :staff_invitation_failed (compensating event)
  """

  @behaviour KlassHero.Shared.Domain.Ports.Driving.ForHandlingIntegrationEvents

  alias KlassHero.Accounts
  alias KlassHero.Accounts.Domain.Events.AccountsIntegrationEvents
  alias KlassHero.Accounts.UserNotifier
  alias KlassHero.Shared.Adapters.Driven.Persistence.MapperHelpers
  alias KlassHero.Shared.Domain.Events.IntegrationEvent
  alias KlassHero.Shared.IntegrationEventPublishing

  require Logger

  @impl true
  def subscribed_events, do: [:staff_member_invited]

  @impl true
  def handle_event(%IntegrationEvent{event_type: :staff_member_invited, payload: payload}) do
    payload = MapperHelpers.normalize_keys(payload)

    case Map.fetch(payload, :email) do
      {:ok, email} ->
        case Accounts.get_user_by_email(email) do
          nil -> handle_new_user(payload)
          user -> handle_existing_user(payload, user)
        end

      :error ->
        Logger.error("[StaffInvitationHandler] Missing :email in staff_member_invited payload")
        {:error, :invalid_payload}
    end
  end

  def handle_event(_event), do: :ignore

  defp handle_new_user(%{
         email: email,
         staff_member_id: staff_member_id,
         provider_id: provider_id,
         first_name: first_name,
         business_name: business_name,
         raw_token: raw_token
       }) do
    url =
      "#{Application.get_env(:klass_hero, :app_base_url, "http://localhost:4000")}/users/staff-invitation/#{raw_token}"

    case UserNotifier.deliver_staff_invitation(
           email,
           %{business_name: business_name, first_name: first_name},
           url
         ) do
      {:ok, _} ->
        emit_sent(staff_member_id, provider_id)

      {:error, reason} ->
        Logger.error("[StaffInvitationHandler] Failed to deliver invitation email",
          email: email,
          staff_member_id: staff_member_id,
          reason: inspect(reason)
        )

        emit_failed(staff_member_id, provider_id, inspect(reason))
    end
  end

  defp handle_existing_user(
         %{email: email, staff_member_id: staff_member_id, provider_id: provider_id, business_name: business_name},
         user
       ) do
    dashboard_url =
      "#{Application.get_env(:klass_hero, :app_base_url, "http://localhost:4000")}/staff/dashboard"

    case UserNotifier.deliver_staff_added_notification(email, %{
           business_name: business_name,
           name: user.name,
           dashboard_url: dashboard_url
         }) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.error(
          "[StaffInvitationHandler] Failed to deliver staff-added notification (user linked but not notified)",
          email: email,
          staff_member_id: staff_member_id,
          reason: inspect(reason)
        )
    end

    # Emit unconditionally regardless of notification delivery.
    # Triggers staff linkage downstream (no provider profile — ADR-0005).
    Accounts.emit_staff_user_registered(user.id, staff_member_id, provider_id)
  end

  defp emit_sent(staff_member_id, provider_id) do
    staff_member_id
    |> AccountsIntegrationEvents.staff_invitation_sent(%{provider_id: provider_id})
    |> IntegrationEventPublishing.publish_critical("staff_invitation_sent",
      staff_member_id: staff_member_id
    )
  end

  defp emit_failed(staff_member_id, provider_id, reason) do
    staff_member_id
    |> AccountsIntegrationEvents.staff_invitation_failed(%{
      provider_id: provider_id,
      reason: reason
    })
    |> IntegrationEventPublishing.publish_critical("staff_invitation_failed",
      staff_member_id: staff_member_id
    )
  end
end
