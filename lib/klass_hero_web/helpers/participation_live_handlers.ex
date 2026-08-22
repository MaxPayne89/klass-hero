defmodule KlassHeroWeb.Helpers.ParticipationLiveHandlers do
  @moduledoc """
  Shared `handle_event` bodies for the provider and staff participation LiveViews.

  The check-in, check-out, and note-submission flows are identical across both
  surfaces; only the post-success participation reload differs (staff reloads through a
  program-assignment authorization gate). Callers pass their own `reload_fn`
  (a `socket -> socket` function, typically `&load_session_data/1`) so that
  divergence stays in the LiveView while the orchestration lives here.

  `session_refusal_message/1` is the one exception to "these two surfaces": the two
  *sessions list* LiveViews call it too, because a refused session write should not
  read differently depending on which page asked.

  The `find_participation_record/2` lookup below is **not** the authorization
  check. It reads the roster already in the socket, for the "Record not found"
  flash and the `child_id` on the failure log. Until #1353 it was the only thing
  standing between an actor and a child's attendance record — not by checking
  anything, but because an authorized query had populated that assign at mount.
  `KlassHero.Participation` now authorizes every attendance write against the
  caller's scope, so this is defence in depth and a UX affordance.
  """

  use Gettext, backend: KlassHeroWeb.Gettext

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias KlassHeroWeb.Helpers.ParticipationEditHelpers
  alias Phoenix.LiveView.Socket

  require Logger

  @type reload_fn :: (Socket.t() -> Socket.t())

  @doc "Records a check-in for the given record, then reloads via `reload_fn`."
  @spec check_in(Socket.t(), String.t(), reload_fn()) :: {:noreply, Socket.t()}
  def check_in(socket, record_id, reload_fn) do
    case ParticipationEditHelpers.find_participation_record(socket, record_id) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Record not found"))}

      record ->
        case KlassHero.Participation.record_check_in(socket.assigns.current_scope, record.id) do
          {:ok, _record} ->
            {:noreply,
             socket
             |> put_flash(:info, gettext("Child checked in successfully"))
             |> reload_fn.()}

          {:error, :unauthorized} ->
            {:noreply, put_flash(socket, :error, gettext("You are not assigned to this program"))}

          {:error, reason} ->
            Logger.error("[ParticipationLiveHandlers.check_in] Failed to check in",
              record_id: record_id,
              child_id: record.child_id,
              reason: inspect(reason)
            )

            {:noreply, put_flash(socket, :error, gettext("Failed to check in: %{reason}", reason: inspect(reason)))}
        end
    end
  end

  @doc "Records a check-out for the given record, clearing its checkout form, then reloads."
  @spec confirm_checkout(Socket.t(), String.t(), map(), reload_fn()) :: {:noreply, Socket.t()}
  def confirm_checkout(socket, record_id, params, reload_fn) do
    notes = Map.get(params, "notes")

    case ParticipationEditHelpers.find_participation_record(socket, record_id) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Record not found"))}

      record ->
        case KlassHero.Participation.record_check_out(socket.assigns.current_scope, record.id, notes: notes) do
          {:ok, _record} ->
            {:noreply,
             socket
             |> put_flash(:info, gettext("Child checked out successfully"))
             |> assign(:checkout_form_expanded, nil)
             |> assign(:checkout_forms, Map.delete(socket.assigns.checkout_forms, record_id))
             |> reload_fn.()}

          {:error, :unauthorized} ->
            {:noreply, put_flash(socket, :error, gettext("You are not assigned to this program"))}

          {:error, reason} ->
            Logger.error("[ParticipationLiveHandlers.confirm_checkout] Failed to check out",
              record_id: record_id,
              child_id: record.child_id,
              reason: inspect(reason)
            )

            {:noreply, put_flash(socket, :error, gettext("Failed to check out: %{reason}", reason: inspect(reason)))}
        end
    end
  end

  @doc "Submits a session note for the given record, clearing its note form, then reloads."
  @spec submit_note(Socket.t(), String.t(), map(), reload_fn()) :: {:noreply, Socket.t()}
  def submit_note(socket, record_id, params, reload_fn) do
    case ParticipationEditHelpers.find_participation_record(socket, record_id) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Record not found"))}

      _record ->
        content = Map.get(params, "content", "")

        case KlassHero.Participation.submit_session_note(%{
               participation_record_id: record_id,
               provider_id: socket.assigns.provider_id,
               content: content
             }) do
          {:ok, _note} ->
            {:noreply,
             socket
             |> put_flash(:info, gettext("Session note submitted for review"))
             |> assign(:note_form_expanded, nil)
             |> assign(:note_forms, Map.delete(socket.assigns.note_forms, record_id))
             |> reload_fn.()}

          {:error, :blank_content} ->
            {:noreply, put_flash(socket, :error, gettext("Note content cannot be blank"))}

          {:error, :duplicate_note} ->
            {:noreply, put_flash(socket, :error, gettext("You already submitted a note for this record"))}

          {:error, reason} ->
            Logger.error("[ParticipationLiveHandlers.submit_note] Failed",
              record_id: record_id,
              reason: inspect(reason)
            )

            {:noreply, put_flash(socket, :error, gettext("Failed to submit note"))}
        end
    end
  end

  @doc """
  Completes the session the page is showing, then reloads via `reload_fn`.

  The session id comes from `socket.assigns`, where a mount-time guard put it —
  never from the event params. The sessions lists have to send it from the client
  because they render one row per session; a roster page showing exactly one
  session does not, and taking it back off the client here would hand a tampered
  event the id the context gate exists to check (#1373).
  """
  @spec complete_session(Socket.t(), reload_fn()) :: {:noreply, Socket.t()}
  def complete_session(socket, reload_fn) do
    session_id = socket.assigns.session_id

    case KlassHero.Participation.complete_session(socket.assigns.current_scope, session_id) do
      {:ok, _session} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Session completed successfully"))
         |> reload_fn.()}

      {:error, reason} when reason in [:unauthorized, :not_found, :program_closed] ->
        {:noreply, put_flash(socket, :error, session_refusal_message(reason))}

      {:error, reason} ->
        Logger.error("[ParticipationLiveHandlers.complete_session] Failed to complete session",
          session_id: session_id,
          reason: inspect(reason)
        )

        {:noreply, put_flash(socket, :error, gettext("Failed to complete session: %{reason}", reason: inspect(reason)))}
    end
  end

  @doc """
  The flash for a session write `KlassHero.Participation` refused.

  One function rather than a literal at each surface. Before #1373 the closed-program
  sentence was copy-pasted at three call sites and the two sessions lists disagreed
  about whether the distinction existed at all — ADR-0019's argument about a rule
  respelled at N surfaces, applied to the copy that reports it.

  `:not_found` deliberately answers the same as `:unauthorized`. The sessions lists
  send a client-supplied session id, and `Participation` resolves the session before
  it authorizes, so a distinct "no such session" would let a tampering client tell
  *exists but is not yours* from *does not exist* and enumerate ids. The staffing
  panel in the same file already states the rule — "foreign and unknown are
  indistinguishable, leaking no oracle" — and the guard this replaced happened to
  honour it by collapsing every lookup failure into a refusal. The reason still
  reaches the log; only the user-visible answer is flattened.
  """
  @spec session_refusal_message(:unauthorized | :not_found | :program_closed) :: String.t()
  def session_refusal_message(:program_closed),
    do: gettext("This program has closed. Its sessions are no longer available.")

  def session_refusal_message(reason) when reason in [:unauthorized, :not_found], do: gettext("Unauthorized")
end
