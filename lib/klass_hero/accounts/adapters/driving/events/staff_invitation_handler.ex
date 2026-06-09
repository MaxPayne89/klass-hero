defmodule KlassHero.Accounts.Adapters.Driving.Events.StaffInvitationHandler do
  @moduledoc """
  Integration event handler for `:staff_member_invited` events from Provider context.

  Sends the invitation email (with the accept-link token) and emits
  `:staff_invitation_sent`, or `:staff_invitation_failed` on delivery failure.

  Per ADR-0005 (#967) every invitee — new or existing account — goes through the
  accept screen, which branches on login state (register / log-in-to-link /
  one-click link). The handler no longer auto-links existing users at invite time;
  linking happens only with authenticated, email-matched consent on the accept screen.
  """

  @behaviour KlassHero.Shared.Domain.Ports.Driving.ForHandlingIntegrationEvents

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
      {:ok, _email} ->
        deliver_invitation(payload)

      :error ->
        Logger.error("[StaffInvitationHandler] Missing :email in staff_member_invited payload")
        {:error, :invalid_payload}
    end
  end

  def handle_event(_event), do: :ignore

  defp deliver_invitation(%{
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
