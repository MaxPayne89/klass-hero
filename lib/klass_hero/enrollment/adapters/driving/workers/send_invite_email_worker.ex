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

      # Failing the invite here is what makes it visible: left :pending it would sit
      # forever with no email sent and nothing to show the provider. A resend mints a
      # fresh token.
      {:ok, %BulkEnrollmentInvite{invite_token: nil} = invite} ->
        Logger.warning("[SendInviteEmailWorker] Invite has no token", invite_id: invite_id)

        invite
        |> Enrollment.transition_invite(%{
          status: :failed,
          error_details: "Invite link could not be generated (no token). Please resend."
        })
        |> resolve_tokenless(job)

      {:ok, %BulkEnrollmentInvite{} = invite} ->
        send_and_transition(invite, program_name, job)
    end
  end

  @doc """
  The Oban outcome a tokenless invite deserves, given whether failing it stuck.

  Split from the branch it serves because no fixture can reach the error arm: the
  non-pending guard in `execute/1` catches every invite that is not `:pending` before
  the branch runs, and `transition_changeset/2` validates against the refetched row,
  so `pending -> :failed` is legal by the time we get here. Injecting the result is
  the only way this decision goes red.
  """
  @spec resolve_tokenless({:ok, BulkEnrollmentInvite.t()} | {:error, term()}, Oban.Job.t()) ::
          {:cancel, String.t()} | {:error, term()}
  # The nil token is beyond retry — every attempt re-reads it — so once the invite is
  # marked failed there is nothing left worth spending attempts on.
  def resolve_tokenless({:ok, _invite}, %Oban.Job{}), do: {:cancel, "invite has no token"}

  # The token is beyond retry; this write is not. `{:cancel, _}` would land the job in
  # `cancelled`, which the compensation sweep does not scan — cancelling is a decision
  # the code made rather than a death it failed to observe — so a lost write would
  # leave the invite :pending forever with nothing to retry it (#1248). Erroring hands
  # it back to Oban, and the final attempt to the sweep.
  def resolve_tokenless({:error, reason}, %Oban.Job{} = job) do
    Logger.critical("[SendInviteEmailWorker] Could not fail a tokenless invite",
      invite_id: job.args["invite_id"],
      reason: inspect(reason)
    )

    TracedWorker.compensate_if_final(__MODULE__, job, reason)

    {:error, reason}
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
