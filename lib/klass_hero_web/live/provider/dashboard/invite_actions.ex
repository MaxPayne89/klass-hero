defmodule KlassHeroWeb.Provider.Dashboard.InviteActions do
  @moduledoc """
  Shared Resend / Remove handling for the provider-dashboard sub-LiveViews.

  Two tabs act on the same invite through the same facade calls but hold different
  lists: ProgramsLive shows one program's roster, OverviewLive the provider-wide
  outstanding set (#1073). Only the reload differs, so each caller passes its own
  `refresh` and this module owns the shared part — the mapping from
  `Enrollment.resend_invite/2` and `delete_invite/2` results to a user-facing flash.

  `refresh` runs only on success; a failed call changed nothing worth re-reading.

  Follows the `Chrome`/`Params`/`Uploads` precedent in this directory: shared
  sub-LiveView behaviour lives beside them, not duplicated into each tab.
  """

  use Gettext, backend: KlassHeroWeb.Gettext

  import Phoenix.LiveView, only: [put_flash: 3]

  alias KlassHero.Enrollment
  alias Phoenix.LiveView.Socket

  require Logger

  @typedoc "Reloads the caller's own invite list after a successful action."
  @type refresh :: (Socket.t() -> Socket.t())

  @doc """
  Resends an invite, refreshing via `refresh` on success. Returns the socket.
  """
  @spec resend(Socket.t(), String.t(), String.t(), refresh()) :: Socket.t()
  def resend(socket, invite_id, provider_id, refresh) when is_function(refresh, 1) do
    case Enrollment.resend_invite(invite_id, provider_id) do
      {:ok, _invite} ->
        socket |> refresh.() |> put_flash(:info, gettext("Invite resent successfully."))

      {:error, :not_resendable} ->
        put_flash(socket, :error, gettext("This invite cannot be resent."))

      {:error, reason} ->
        Logger.warning("[Dashboard.InviteActions] Resend invite failed unexpectedly",
          invite_id: invite_id,
          reason: inspect(reason)
        )

        put_flash(socket, :error, gettext("Failed to resend invite."))
    end
  end

  @doc """
  Removes an invite, refreshing via `refresh` on success. Returns the socket.
  """
  @spec delete(Socket.t(), String.t(), String.t(), refresh()) :: Socket.t()
  def delete(socket, invite_id, provider_id, refresh) when is_function(refresh, 1) do
    case Enrollment.delete_invite(invite_id, provider_id) do
      :ok ->
        socket |> refresh.() |> put_flash(:info, gettext("Invite removed."))

      {:error, :not_found} ->
        put_flash(socket, :error, gettext("Invite not found."))

      {:error, :delete_failed} ->
        put_flash(socket, :error, gettext("Could not remove invite."))
    end
  end
end
