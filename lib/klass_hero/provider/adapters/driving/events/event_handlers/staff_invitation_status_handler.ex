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

  @behaviour KlassHero.Shared.ForHandlingEvents

  alias KlassHero.Provider
  alias KlassHero.Provider.StaffMember
  alias KlassHero.Repo
  alias KlassHero.Shared.Domain.Events.Event

  require Logger

  @impl true
  def subscribed_events, do: [:staff_invitation_sent, :staff_invitation_failed, :staff_user_registered]

  @impl true
  def handle_event(%Event{event_type: :staff_invitation_sent, payload: payload}) do
    transition_and_persist(payload, :sent, fn transitioned ->
      %{transitioned | invitation_sent_at: DateTime.utc_now()}
    end)
  end

  def handle_event(%Event{event_type: :staff_invitation_failed, payload: payload}) do
    transition_and_persist(payload, :failed)
  end

  def handle_event(%Event{event_type: :staff_user_registered, payload: payload}) do
    # Uses the same accept flow as the synchronous path (ADR-0005: never creates a ProviderProfile).
    with {:ok, user_id} <- Map.fetch(payload, :user_id),
         {:ok, staff_member_id} <- Map.fetch(payload, :staff_member_id),
         {:ok, staff} <- Provider.get_staff_member(staff_member_id) do
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

  # Idempotent: replays where the invitation is already past :sent/:pending are treated as success.
  defp accept_idempotently(staff, user_id) do
    case Provider.accept_staff_invitation(staff, user_id) do
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
         {:ok, staff} <- Provider.get_staff_member(staff_member_id),
         {:ok, transitioned} <- StaffMember.transition_invitation(staff, new_status),
         updated = update_fn.(transitioned),
         {:ok, _persisted} <- persist_invitation_transition(staff, updated) do
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

  # Casts the transitioned invitation fields onto the freshly-loaded row so Ecto
  # sees a real status change (the state-machine guard already ran upstream).
  defp persist_invitation_transition(%StaffMember{} = original, %StaffMember{} = updated) do
    original
    |> StaffMember.invitation_changeset(%{
      invitation_status: updated.invitation_status,
      invitation_sent_at: updated.invitation_sent_at
    })
    |> Repo.update()
  end
end
