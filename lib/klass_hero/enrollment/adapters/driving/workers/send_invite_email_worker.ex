defmodule KlassHero.Enrollment.Adapters.Driving.Workers.SendInviteEmailWorker do
  @moduledoc """
  Oban worker that sends a single enrollment invitation email.

  Fetches the invite, builds the email via the configured notifier adapter,
  and transitions the invite status from `pending` to `invite_sent`.
  """

  use KlassHero.Shared.RateLimitedEmailWorker, queue: :email, max_attempts: 3

  alias KlassHero.Enrollment
  alias KlassHero.Enrollment.Adapters.Driven.Notifications.InviteEmailNotifier
  alias KlassHero.Enrollment.BulkEnrollmentInvite

  require Logger

  @impl true
  def execute(%Oban.Job{args: %{"invite_id" => invite_id, "program_name" => program_name}}) do
    case Enrollment.get_invite(invite_id) do
      {:error, :not_found} ->
        Logger.warning("[SendInviteEmailWorker] Invite not found", invite_id: invite_id)
        :ok

      # Oban may retry or event may be re-dispatched — skip non-pending to avoid duplicate emails.
      {:ok, %BulkEnrollmentInvite{status: status}} when status != :pending ->
        Logger.info("[SendInviteEmailWorker] Skipping non-pending invite",
          invite_id: invite_id,
          status: status
        )

        :ok

      {:ok, %BulkEnrollmentInvite{invite_token: nil}} ->
        Logger.warning("[SendInviteEmailWorker] Invite has no token", invite_id: invite_id)
        {:error, "invite has no token"}

      {:ok, %BulkEnrollmentInvite{} = invite} ->
        send_and_transition(invite, program_name)
    end
  end

  defp send_and_transition(invite, program_name) do
    invite_url = "#{base_url()}/invites/#{invite.invite_token}"

    case InviteEmailNotifier.send_invite(invite, program_name, invite_url) do
      {:ok, _email} ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        # Email already delivered — return :ok even if status transition fails to prevent Oban retry/duplicate send.
        case Enrollment.transition_invite(invite, %{
               status: :invite_sent,
               invite_sent_at: now
             }) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.critical(
              "[SendInviteEmailWorker] Email sent but status transition failed",
              invite_id: invite.id,
              reason: inspect(reason)
            )

            :ok
        end

      {:error, reason} ->
        Logger.error("[SendInviteEmailWorker] Email delivery failed",
          invite_id: invite.id,
          reason: inspect(reason)
        )

        Enrollment.transition_invite(invite, %{
          status: :failed,
          error_details: "Email delivery failed: #{inspect(reason)}"
        })

        {:error, reason}
    end
  end

  # Reads URL config at runtime — referencing KlassHeroWeb.Endpoint directly would violate boundary rules.
  defp base_url do
    endpoint_config = Application.get_env(:klass_hero, KlassHeroWeb.Endpoint, [])
    url_config = Keyword.get(endpoint_config, :url, [])
    scheme = Keyword.get(url_config, :scheme, "http")
    host = Keyword.get(url_config, :host, "localhost")
    port = Keyword.get(url_config, :port)

    case {scheme, port} do
      {_, nil} -> "#{scheme}://#{host}"
      {"https", 443} -> "https://#{host}"
      {"http", 80} -> "http://#{host}"
      {_, port} -> "#{scheme}://#{host}:#{port}"
    end
  end
end
