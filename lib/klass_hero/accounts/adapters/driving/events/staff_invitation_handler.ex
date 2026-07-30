defmodule KlassHero.Accounts.Adapters.Driving.Events.StaffInvitationHandler do
  @moduledoc """
  Integration event handler for `:staff_member_invited` events from Provider context.

  Sends the invitation email (with the accept-link token) and emits
  `:staff_invitation_sent`, or `:staff_invitation_failed` on delivery failure.

  Per ADR-0005 (#967) every invitee — new or existing account — goes through the
  accept screen, which branches on login state (register / log-in-to-link /
  one-click link). The handler picks the email copy based on whether an account
  already exists, but never auto-links: linking happens only with authenticated,
  email-matched consent on the accept screen.
  """

  @behaviour KlassHero.Shared.ForHandlingEvents

  alias KlassHero.Accounts
  alias KlassHero.Accounts.Domain.Events.AccountsEvents
  alias KlassHero.Accounts.User
  alias KlassHero.Accounts.UserNotifier
  alias KlassHero.Shared.Adapters.Driven.Persistence.MapperHelpers
  alias KlassHero.Shared.Domain.Events.Event
  alias KlassHero.Shared.Outbox

  require Logger

  @impl true
  def subscribed_events, do: [:staff_member_invited]

  @impl true
  def handle_event(%Event{event_type: :staff_member_invited, payload: payload}) do
    payload = MapperHelpers.normalize_keys(payload)

    case Map.fetch(payload, :email) do
      {:ok, email} ->
        deliver_invitation(payload, Accounts.get_user_by_email(email))

      :error ->
        Logger.error("[StaffInvitationHandler] Missing :email in staff_member_invited payload")
        {:error, :invalid_payload}
    end
  end

  def handle_event(_event), do: :ignore

  defp deliver_invitation(payload, recipient) do
    %{
      email: email,
      staff_member_id: staff_member_id,
      provider_id: provider_id,
      raw_token: raw_token
    } = payload

    url =
      "#{Application.get_env(:klass_hero, :app_base_url, "http://localhost:4000")}/users/staff-invitation/#{raw_token}"

    case send_invitation_email(payload, recipient, url) do
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

  # No account → registration-style invitation
  defp send_invitation_email(%{email: email, business_name: business_name, first_name: first_name}, nil, url) do
    UserNotifier.deliver_staff_invitation(email, %{business_name: business_name, first_name: first_name}, url)
  end

  # Existing account → log-in-and-link invitation (no auto-link)
  defp send_invitation_email(%{email: email, business_name: business_name}, %User{name: name}, url) do
    UserNotifier.deliver_staff_link_invitation(email, %{business_name: business_name, name: name}, url)
  end

  defp emit_sent(staff_member_id, provider_id) do
    staff_member_id
    |> AccountsEvents.staff_invitation_sent(%{provider_id: provider_id})
    |> then(&Outbox.stage(KlassHero.Accounts, &1))
  end

  defp emit_failed(staff_member_id, provider_id, reason) do
    staff_member_id
    |> AccountsEvents.staff_invitation_failed(%{
      provider_id: provider_id,
      reason: reason
    })
    |> then(&Outbox.stage(KlassHero.Accounts, &1))
  end
end
