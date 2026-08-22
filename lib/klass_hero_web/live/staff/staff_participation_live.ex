defmodule KlassHeroWeb.Staff.StaffParticipationLive do
  use KlassHeroWeb, :live_view

  import KlassHeroWeb.Helpers.ParticipationEditHelpers,
    only: [
      expand_form: 7,
      cancel_form: 4,
      update_form: 6,
      find_participation_record: 2
    ]

  alias KlassHero.Participation
  alias KlassHero.Provider
  alias KlassHero.Provider.ReadModels.SessionStaffing
  alias KlassHeroWeb.Helpers.ParticipationEditHelpers
  alias KlassHeroWeb.Helpers.ParticipationLiveHandlers
  alias KlassHeroWeb.Theme

  require Logger

  @impl true
  def mount(%{"session_id" => session_id}, _session, socket) do
    staff_member = socket.assigns.current_scope.staff_member

    socket =
      socket
      |> assign(:page_title, gettext("Manage Participation"))
      |> assign(:active_nav, :roster)
      |> assign(:session_id, session_id)
      |> assign(:provider_id, staff_member.provider_id)
      |> assign(:staff_member, staff_member)
      |> assign(:session, nil)
      |> assign(:participation_records, [])
      |> assign(:checkout_form_expanded, nil)
      |> assign(:checkout_forms, %{})
      |> assign(:note_form_expanded, nil)
      |> assign(:note_forms, %{})
      |> assign(:edit_form_expanded, nil)
      |> assign(:edit_forms, %{})
      |> assign(:record_note_map, %{})

    if connected?(socket) do
      # One topic for everything this provider does — attendance and session notes
      # alike. Notes used to arrive on their own registry-derived topics, which
      # carried every provider's notes, not just this one's.
      Phoenix.PubSub.subscribe(KlassHero.PubSub, Participation.provider_topic(staff_member.provider_id))
    end

    {:ok, load_session_data(socket)}
  end

  @impl true
  def handle_event("check_in", %{"id" => record_id}, socket) do
    ParticipationLiveHandlers.check_in(socket, record_id, &load_session_data/1)
  end

  @impl true
  def handle_event("expand_checkout_form", %{"id" => record_id}, socket) do
    {:noreply,
     expand_form(
       socket,
       record_id,
       "checkout",
       "notes",
       "",
       :checkout_form_expanded,
       :checkout_forms
     )}
  end

  @impl true
  def handle_event("cancel_checkout", %{"id" => record_id}, socket) do
    {:noreply, cancel_form(socket, record_id, :checkout_form_expanded, :checkout_forms)}
  end

  @impl true
  def handle_event("update_checkout_notes", %{"id" => record_id, "checkout" => %{"notes" => notes}}, socket) do
    {:noreply, update_form(socket, record_id, notes, "checkout", "notes", :checkout_forms)}
  end

  @impl true
  def handle_event("confirm_checkout", %{"id" => record_id, "checkout" => params}, socket) do
    ParticipationLiveHandlers.confirm_checkout(socket, record_id, params, &load_session_data/1)
  end

  @impl true
  def handle_event("expand_note_form", %{"id" => record_id}, socket) do
    {:noreply, expand_form(socket, record_id, "note", "content", "", :note_form_expanded, :note_forms)}
  end

  @impl true
  def handle_event("cancel_note", %{"id" => record_id}, socket) do
    {:noreply, cancel_form(socket, record_id, :note_form_expanded, :note_forms)}
  end

  @impl true
  def handle_event("update_note_content", %{"id" => record_id, "note" => %{"content" => content}}, socket) do
    {:noreply, update_form(socket, record_id, content, "note", "content", :note_forms)}
  end

  @impl true
  def handle_event("submit_note", %{"id" => record_id, "note" => params}, socket) do
    ParticipationLiveHandlers.submit_note(socket, record_id, params, &load_session_data/1)
  end

  @impl true
  def handle_event("expand_edit_form", %{"id" => record_id}, socket) do
    case find_participation_record(socket, record_id) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Record not found"))}

      record ->
        form =
          to_form(
            %{"notes" => ParticipationEditHelpers.default_edit_notes(record), "check_out_at" => ""},
            as: "edit"
          )

        {:noreply,
         socket
         |> assign(:edit_form_expanded, record_id)
         |> assign(:edit_forms, Map.put(socket.assigns.edit_forms, record_id, form))}
    end
  end

  @impl true
  def handle_event("cancel_edit", %{"id" => record_id}, socket) do
    {:noreply,
     socket
     |> assign(:edit_form_expanded, nil)
     |> assign(:edit_forms, Map.delete(socket.assigns.edit_forms, record_id))}
  end

  @impl true
  def handle_event("update_edit_form", %{"id" => record_id, "edit" => params}, socket) do
    form = to_form(params, as: "edit")

    {:noreply, assign(socket, :edit_forms, Map.put(socket.assigns.edit_forms, record_id, form))}
  end

  @impl true
  def handle_event("submit_edit", %{"id" => record_id, "edit" => params}, socket) do
    record = find_participation_record(socket, record_id)

    with {:record, record} when not is_nil(record) <- {:record, record},
         {:ok, correction} <- ParticipationEditHelpers.build_edit_correction(record, params),
         {:ok, _} <- Participation.correct_attendance(socket.assigns.current_scope, record_id, correction) do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Record updated"))
       |> assign(:edit_form_expanded, nil)
       |> assign(:edit_forms, Map.delete(socket.assigns.edit_forms, record_id))
       |> load_session_data()}
    else
      {:record, nil} ->
        {:noreply, put_flash(socket, :error, gettext("Record not found"))}

      {:error, :invalid_datetime} ->
        {:noreply, put_flash(socket, :error, gettext("Departure time is not a valid date and time"))}

      {:error, :no_changes} ->
        {:noreply, put_flash(socket, :info, gettext("Nothing to update"))}

      {:error, reason} ->
        Logger.error("[StaffParticipationLive.submit_edit] Failed",
          record_id: record_id,
          reason: inspect(reason)
        )

        {:noreply, put_flash(socket, :error, gettext("Failed to update record"))}
    end
  end

  @impl true
  def handle_info({:attendance_changed, %{record_id: record_id}}, socket) do
    {:noreply, update_participation_record(socket, record_id)}
  end

  @impl true
  def handle_info(:session_notes_changed, socket) do
    {:noreply, load_session_data(socket)}
  end

  @impl true
  def handle_info(_message, socket) do
    {:noreply, socket}
  end

  # Why the refusal — for the message only. The refusal itself is
  # `SessionStaffing.staffed_by?/2`'s, and it already refuses a Closed Program on
  # its own; this only reads the reason off the same struct so the flash can say
  # which of the two it was, without a second round trip (#1082).
  defp refusal_reason(%SessionStaffing{program_closed?: true}), do: :program_closed
  defp refusal_reason(_staffing), do: :not_assigned

  defp refusal_message(:program_closed), do: gettext("This program has closed. Its sessions are no longer available.")

  defp refusal_message(:not_assigned), do: gettext("You are not assigned to this session")

  defp load_session_data(socket) do
    session_id = socket.assigns.session_id

    case Participation.get_session_with_roster_enriched(session_id) do
      {:ok, session} ->
        # Defence in depth, and a UX affordance: it keeps an unauthorized roster off
        # the screen instead of rendering a page whose every button fails. The
        # authorization of record is in the context now (ADR-0017) — this gate is no
        # longer the only thing standing between staff and a child's record (#1353).
        # Asked at session grain, so it agrees with the context rather than
        # shadowing it with a coarser answer (#783).
        staffing = Provider.get_session_staffing(session_id)

        if SessionStaffing.staffed_by?(staffing, socket.assigns.staff_member.id) do
          socket
          |> assign(:session, session)
          |> assign(:participation_records, session.participation_records || [])
          |> assign(:session_error, nil)
          |> load_provider_notes()
        else
          reason = refusal_reason(staffing)

          Logger.warning(
            "[StaffParticipationLive] Unauthorized access to session",
            session_id: session_id,
            staff_member_id: socket.assigns.staff_member.id,
            reason: reason
          )

          socket
          |> put_flash(:error, refusal_message(reason))
          |> push_navigate(to: ~p"/staff/sessions")
        end

      {:error, :not_found} ->
        Logger.warning(
          "[StaffParticipationLive.load_session_data] Session not found",
          session_id: session_id
        )

        socket
        |> put_flash(:error, gettext("Session not found"))
        |> push_navigate(to: ~p"/staff/sessions")
    end
  end

  defp update_participation_record(socket, record_id) do
    case Participation.get_session_with_roster_enriched(socket.assigns.session_id) do
      {:ok, session} ->
        socket
        |> assign(:session, session)
        |> assign(:participation_records, session.participation_records || [])

      {:error, reason} ->
        Logger.error(
          "[StaffParticipationLive.update_participation_record] Failed to refresh session",
          session_id: socket.assigns.session_id,
          record_id: record_id,
          reason: inspect(reason)
        )

        put_flash(socket, :warning, gettext("Unable to refresh roster. Please reload."))
    end
  end

  defp load_provider_notes(socket) do
    provider_id = socket.assigns.provider_id
    records = socket.assigns.participation_records
    record_ids = Enum.map(records, & &1.id)

    notes =
      Participation.list_session_notes_by_records_and_provider(record_ids, provider_id)

    notes_by_record =
      Map.new(notes, fn note -> {to_string(note.participation_record_id), note} end)

    assign(socket, :record_note_map, notes_by_record)
  end
end
