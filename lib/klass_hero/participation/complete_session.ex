defmodule KlassHero.Participation.CompleteSession do
  @moduledoc """
  Completes an in-progress session and sweeps its roster in one transaction.

  Lives at the context root rather than in `Sessions` because it spans two
  entities under one transaction — the same reason `Provider.OffboardStaffMember`
  does. The session row and the still-`registered` children going `absent` are
  one fact: a completed session whose stragglers were never marked absent is a
  half-finished write, so `Sessions` supplies the session half,
  `Attendance.mark_roster_absent_for_session/1` the roster half, and the
  transaction opened here holds them together.

  Authorized at this boundary rather than by the caller, for the reason ADR-0017
  gives for attendance: a guard that lives in one of four callers is not a guard.
  Until #1373 the provider sessions list handed this a client-supplied id with no
  check at all.
  """

  use KlassHero.Shared.Tracing

  alias KlassHero.Accounts.Scope
  alias KlassHero.Participation.Attendance
  alias KlassHero.Participation.Events
  alias KlassHero.Participation.Notifications
  alias KlassHero.Participation.ProgramProviderResolver
  alias KlassHero.Participation.ProgramSession
  alias KlassHero.Participation.SessionAuthorization
  alias KlassHero.Participation.Sessions
  alias KlassHero.Shared.Outbox

  require Logger

  @context KlassHero.Participation

  @doc """
  Completes an in-progress session on behalf of `scope`, marking all registered
  (not checked-in) children as absent.

  Authorized at this boundary rather than by the caller, for the reason ADR-0017
  gives for attendance: a guard that lives in one of four callers is not a guard.
  Completing a session marks every remaining registered child absent, and until
  #1373 the provider sessions list handed this function a client-supplied id with
  no check at all.

  Returns `{:ok, session}`, `{:error, :not_found}`, `{:error, :unauthorized}`,
  `{:error, :program_closed}`, or `{:error, :invalid_status_transition}`.
  """
  @spec execute(Scope.t(), String.t()) ::
          {:ok, ProgramSession.t()} | {:error, :not_found | SessionAuthorization.refusal() | :invalid_status_transition}
  def execute(%Scope{} = scope, session_id) when is_binary(session_id) do
    context_span entity: "session" do
      with {:ok, session} <- Sessions.get_session(session_id),
           {:ok, _role} <- SessionAuthorization.authorize_lifecycle(scope, session),
           {:ok, completed} <- ProgramSession.complete(session),
           {:ok, {persisted, events}} <- persist_with_events(completed) do
        Notifications.notify_all(events)
        {:ok, persisted}
      end
    end
  end

  # ============================================================================
  # Event publishing helpers
  # ============================================================================

  defp session_completed_event(session) do
    extra_payload = resolve_provider_details(session.program_id)
    Events.session_completed(session, extra_payload: extra_payload)
  end

  defp resolve_provider_details(program_id) do
    case ProgramProviderResolver.resolve_provider_details(program_id) do
      {:ok, details} ->
        details

      {:error, reason} ->
        Logger.warning("Could not resolve provider details for session_completed event",
          program_id: program_id,
          reason: inspect(reason)
        )

        %{provider_id: "00000000-0000-0000-0000-000000000000", program_title: "Unknown Program"}
    end
  end

  # The absences and the completion are one fact: a completed session whose
  # registered children were never marked absent is a half-finished write.
  defp persist_with_events(completed) do
    Outbox.transact_with_events(@context, fn ->
      with {:ok, persisted} <- Sessions.persist_lifecycle_update(completed),
           {:ok, absence_events} <- Attendance.mark_roster_absent_for_session(persisted) do
        {:ok, persisted, absence_events ++ [session_completed_event(persisted)]}
      end
    end)
  end
end
