defmodule KlassHero.Enrollment.Adapters.Driving.Events.InviteFamilyReadyHandler do
  @moduledoc """
  Integration event handler that creates an enrollment when the Family context
  signals that the parent profile and child have been created from an invite.

  Triggered by `:invite_family_ready` from the Family context.

  ## Flow

  1. Receive `:invite_family_ready` with invite_id, child_id, parent_id, program_id
  2. Fetch invite, validate it is in "registered" status
  3. Create enrollment via the Enrollment facade (direct path, no tier/eligibility checks)
  4. Transition invite: registered -> enrolled, set enrolled_at and enrollment_id
  5. On failure: transition invite -> failed with error details

  ## Idempotency

  - Invite not found -> :ok (likely already processed or cleaned up)
  - Invite not in "registered" status -> :ok (already processed)
  - Duplicate enrollment -> transitions invite to enrolled without enrollment_id
  """

  @behaviour KlassHero.Shared.ForHandlingEvents

  alias KlassHero.Enrollment
  alias KlassHero.Shared.Domain.Events.Event

  require Logger

  @impl true
  def subscribed_events, do: [:invite_family_ready]

  @impl true
  def handle_event(%Event{event_type: :invite_family_ready} = event) do
    %{invite_id: invite_id, child_id: child_id, parent_id: parent_id, program_id: program_id} =
      event.payload

    with {:ok, invite} <- fetch_registered_invite(invite_id),
         {:ok, enrollment} <- create_enrollment(child_id, parent_id, program_id),
         {:ok, _} <- transition_to_enrolled(invite, enrollment) do
      Logger.info("[InviteFamilyReadyHandler] Enrollment created",
        invite_id: invite_id,
        enrollment_id: enrollment.id
      )

      :ok
    else
      {:error, :not_found} ->
        Logger.warning("[InviteFamilyReadyHandler] Invite not found", invite_id: invite_id)
        :ok

      {:error, :not_registered} ->
        Logger.info("[InviteFamilyReadyHandler] Invite already processed", invite_id: invite_id)
        :ok

      {:error, :duplicate_resource} ->
        # Idempotent: enrollment already exists — still transition invite to enrolled
        Logger.info(
          "[InviteFamilyReadyHandler] Enrollment already exists, transitioning invite",
          invite_id: invite_id
        )

        handle_existing_enrollment(invite_id)

      {:error, reason} ->
        Logger.error("[InviteFamilyReadyHandler] Failed",
          invite_id: invite_id,
          reason: inspect(reason)
        )

        Enrollment.fail_invite(invite_id, reason)
        {:error, reason}
    end
  end

  def handle_event(_event), do: :ignore

  # Only act on :registered invites — prevents double-processing or regressing an already-enrolled invite.
  defp fetch_registered_invite(invite_id) do
    case Enrollment.get_invite(invite_id) do
      {:error, :not_found} = err -> err
      {:ok, %{status: :registered} = invite} -> {:ok, invite}
      {:ok, _other} -> {:error, :not_registered}
    end
  end

  # Bulk invites bypass payment/tier/eligibility checks — use "transfer" + "confirmed" directly.
  defp create_enrollment(child_id, parent_id, program_id) do
    Enrollment.create_enrollment(%{
      program_id: program_id,
      child_id: child_id,
      parent_id: parent_id,
      status: :confirmed,
      payment_method: "transfer"
    })
  end

  defp transition_to_enrolled(invite, enrollment) do
    Enrollment.transition_invite(invite, %{
      status: :enrolled,
      enrolled_at: DateTime.utc_now() |> DateTime.truncate(:second),
      enrollment_id: enrollment.id
    })
  end

  # Enrollment exists but invite status may still be :registered — transition it for consistency.
  defp handle_existing_enrollment(invite_id) do
    case Enrollment.get_invite(invite_id) do
      {:ok, %{status: :registered} = invite} ->
        case Enrollment.transition_invite(invite, %{
               status: :enrolled,
               enrolled_at: DateTime.utc_now() |> DateTime.truncate(:second)
             }) do
          {:ok, _} ->
            Logger.info(
              "[InviteFamilyReadyHandler] Transitioned existing-enrollment invite to enrolled",
              invite_id: invite_id
            )

          {:error, reason} ->
            Logger.warning(
              "[InviteFamilyReadyHandler] Failed to transition existing-enrollment invite",
              invite_id: invite_id,
              reason: inspect(reason)
            )
        end

        :ok

      _ ->
        :ok
    end
  end
end
