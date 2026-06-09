defmodule KlassHero.Provider.Adapters.Driving.Events.EventHandlers.StaffInvitationStatusHandler do
  @moduledoc """
  Integration event handler for staff invitation status updates from Accounts context.

  Reacts to:
  - `:staff_invitation_sent` — status :pending → :sent, sets `invitation_sent_at`
  - `:staff_invitation_failed` — status :pending → :failed (compensation)
  - `:staff_user_registered` — status :sent/:pending → :accepted, links `user_id`

  All handlers are idempotent: if the transition is already past the expected
  source state, the handler treats `{:error, :invalid_invitation_transition}` as
  success and logs accordingly.
  """

  @behaviour KlassHero.Shared.Domain.Ports.Driving.ForHandlingIntegrationEvents

  alias KlassHero.Provider.Application.Commands.StaffMembers.AcceptStaffInvitation
  alias KlassHero.Provider.Domain.Models.StaffMember
  alias KlassHero.Shared.Adapters.Driven.Persistence.MapperHelpers
  alias KlassHero.Shared.Domain.Events.IntegrationEvent

  require Logger

  @staff_query Application.compile_env!(:klass_hero, [:provider, :for_querying_staff_members])
  @repository Application.compile_env!(:klass_hero, [:provider, :for_storing_staff_members])

  @impl true
  def subscribed_events, do: [:staff_invitation_sent, :staff_invitation_failed, :staff_user_registered]

  @impl true
  def handle_event(%IntegrationEvent{event_type: :staff_invitation_sent, payload: payload}) do
    payload = MapperHelpers.normalize_keys(payload)

    transition_and_persist(payload, :sent, fn transitioned ->
      %{transitioned | invitation_sent_at: DateTime.utc_now()}
    end)
  end

  def handle_event(%IntegrationEvent{event_type: :staff_invitation_failed, payload: payload}) do
    payload = MapperHelpers.normalize_keys(payload)
    transition_and_persist(payload, :failed)
  end

  def handle_event(%IntegrationEvent{event_type: :staff_user_registered, payload: payload}) do
    payload = MapperHelpers.normalize_keys(payload)

    # Links the User to the StaffMember and accepts the invitation via the same
    # command the synchronous one-click path uses (single definition of "link").
    # Per ADR-0005 this never creates a ProviderProfile.
    with {:ok, user_id} <- Map.fetch(payload, :user_id),
         {:ok, staff_member_id} <- Map.fetch(payload, :staff_member_id),
         {:ok, staff} <- @staff_query.get(staff_member_id) do
      accept_idempotently(staff, user_id)
    else
      :error ->
        Logger.error("[StaffInvitationStatusHandler] Missing :user_id/:staff_member_id in payload")
        {:error, :invalid_payload}

      {:error, reason} ->
        Logger.error("[StaffInvitationStatusHandler] Staff member lookup failed",
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  def handle_event(_event), do: :ignore

  # Idempotent for at-least-once delivery: a replay whose invitation is already
  # past :sent/:pending (e.g. already :accepted) is treated as success.
  defp accept_idempotently(staff, user_id) do
    case AcceptStaffInvitation.execute(staff, user_id) do
      {:ok, _staff} ->
        :ok

      {:error, :invalid_invitation_transition} ->
        Logger.info("[StaffInvitationStatusHandler] Skipping accept (already past)",
          staff_member_id: staff.id
        )

        :ok

      {:error, reason} ->
        Logger.error("[StaffInvitationStatusHandler] Failed to accept invitation",
          staff_member_id: staff.id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp transition_and_persist(payload, new_status, update_fn \\ &Function.identity/1) do
    with {:ok, staff_member_id} <- Map.fetch(payload, :staff_member_id),
         {:ok, staff} <- @staff_query.get(staff_member_id),
         {:ok, transitioned} <- StaffMember.transition_invitation(staff, new_status),
         updated = update_fn.(transitioned),
         {:ok, _persisted} <- @repository.update(updated) do
      Logger.info("[StaffInvitationStatusHandler] Transitioned to #{new_status}",
        staff_member_id: staff_member_id
      )

      :ok
    else
      :error ->
        Logger.error("[StaffInvitationStatusHandler] Missing :staff_member_id in payload")
        {:error, :invalid_payload}

      {:error, :invalid_invitation_transition} ->
        Logger.info("[StaffInvitationStatusHandler] Skipping (already past #{new_status})",
          staff_member_id: payload[:staff_member_id]
        )

        :ok

      {:error, reason} ->
        Logger.error("[StaffInvitationStatusHandler] Failed to transition to #{new_status}",
          staff_member_id: payload[:staff_member_id],
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end
end
