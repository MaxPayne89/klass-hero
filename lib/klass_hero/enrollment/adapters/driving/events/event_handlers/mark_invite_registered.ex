defmodule KlassHero.Enrollment.Adapters.Driving.Events.EventHandlers.MarkInviteRegistered do
  @moduledoc """
  Domain event handler that transitions an invite from invite_sent to registered
  when the guardian claims the invite link.

  Triggered by `:invite_claimed` on the Enrollment DomainEventBus.
  Idempotent: skips if invite is already registered or beyond.
  """

  alias KlassHero.Enrollment
  alias KlassHero.Shared.Domain.Events.Event

  require Logger

  @spec handle(Event.t()) :: :ok | {:error, term()}
  def handle(%Event{event_type: :invite_claimed} = event) do
    %{invite_id: invite_id} = event.payload

    case Enrollment.get_invite(invite_id) do
      {:error, :not_found} ->
        Logger.warning("[MarkInviteRegistered] Invite not found", invite_id: invite_id)
        :ok

      {:ok, invite} ->
        maybe_transition(invite)
    end
  end

  # Idempotent: already at or past registered — replaying must not regress status.
  defp maybe_transition(%{status: status}) when status in [:registered, :enrolled] do
    :ok
  end

  defp maybe_transition(%{status: :invite_sent} = invite) do
    case Enrollment.transition_invite(invite, %{
           status: :registered,
           registered_at: DateTime.utc_now() |> DateTime.truncate(:second)
         }) do
      {:ok, _} ->
        Logger.info("[MarkInviteRegistered] Invite transitioned to registered",
          invite_id: invite.id
        )

        :ok

      {:error, reason} ->
        Logger.error("[MarkInviteRegistered] Failed to transition invite",
          invite_id: invite.id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  # Unexpected status (e.g. pending, failed) — not a valid source for this transition; no-op.
  defp maybe_transition(%{status: status} = invite) do
    Logger.warning("[MarkInviteRegistered] Unexpected status, skipping",
      invite_id: invite.id,
      status: status
    )

    :ok
  end
end
