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
  def execute(%Oban.Job{args: %{"invite_id" => invite_id, "program_name" => program_name}} = job) do
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

      # Every retry re-reads the same nil token, so the remaining attempts are
      # guaranteed waste — cancel rather than spend them. Failing the invite here is
      # what makes it visible: left :pending it would sit forever with no email sent
      # and nothing to show the provider. A resend mints a fresh token.
      # Not backstopped by the compensation sweep, and cannot be: a cancel lands the job in
      # `cancelled`, not `discarded`, which is deliberately out of the sweep's scope because
      # cancelling is a decision the code already handled rather than a death it did not see.
      # So if this transition fails, nothing retries it. Accepted rather than overlooked.
      {:ok, %BulkEnrollmentInvite{invite_token: nil} = invite} ->
        Logger.warning("[SendInviteEmailWorker] Invite has no token", invite_id: invite_id)

        Enrollment.transition_invite(invite, %{
          status: :failed,
          error_details: "Invite link could not be generated (no token). Please resend."
        })

        {:cancel, "invite has no token"}

      {:ok, %BulkEnrollmentInvite{} = invite} ->
        send_and_transition(invite, program_name, job)
    end
  end

  defp send_and_transition(invite, program_name, job) do
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

        # Only once Oban is done retrying. `pending -> :failed` is a one-way door —
        # `:failed` can only go back to `:pending` — and the non-pending guard above
        # then turns every retry into a silent :ok, so failing early both destroys the
        # send the next attempt makes and hides that it did (#1233).
        TracedWorker.compensate_if_final(__MODULE__, job, reason)

        {:error, reason}
    end
  end

  # A rejected transition means the invite is already terminal — sent by a duplicate
  # attempt, or failed by an earlier pass — which is a fact rather than something a later
  # sweep could fix, so it reports `:ignore`.
  @impl true
  def compensate(%Oban.Job{args: %{"invite_id" => invite_id}}, reason) do
    case Enrollment.transition_invite(%{id: invite_id}, %{
           status: :failed,
           error_details: describe(reason)
         }) do
      {:ok, _invite} -> :ok
      {:error, _reason} -> :ignore
    end
  end

  # The sweep cannot recover the failing attempt's reason — a Lifeline discard records
  # none — so the provider gets the fact without a cause rather than "nil".
  defp describe(nil), do: "Email delivery failed and no retries remain"
  defp describe(reason), do: "Email delivery failed: #{inspect(reason)}"

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
