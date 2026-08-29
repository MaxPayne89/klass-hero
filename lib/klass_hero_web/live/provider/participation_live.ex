defmodule KlassHeroWeb.Provider.ParticipationLive do
  use KlassHeroWeb, :live_view

  import KlassHeroWeb.Helpers.ParticipationEditHelpers,
    only: [
      expand_form: 7,
      cancel_form: 4,
      update_form: 6,
      find_participation_record: 2
    ]

  import KlassHeroWeb.ProviderComponents, only: [session_form: 1, session_staffing_modal: 1]

  alias KlassHero.Participation
  alias KlassHero.ProgramCatalog
  alias KlassHero.Provider
  alias KlassHero.Provider.ReadModels.SessionStaffing
  alias KlassHeroWeb.Helpers.ParticipationEditHelpers
  alias KlassHeroWeb.Helpers.ParticipationLiveHandlers
  alias KlassHeroWeb.Helpers.SessionFormHandlers
  alias KlassHeroWeb.Presenters.ProgramStaffingPresenter
  alias KlassHeroWeb.Theme

  require Logger

  @impl true
  def mount(%{"session_id" => session_id}, _session, socket) do
    provider_id = socket.assigns.current_scope.provider.id
    assigned_program_ids = MapSet.new(ProgramCatalog.list_program_ids_for_provider(provider_id))

    socket =
      socket
      |> assign(:page_title, gettext("Manage Participation"))
      |> assign(:active_nav, :roster)
      |> assign(:session_id, session_id)
      |> assign(:provider_id, provider_id)
      |> assign(:assigned_program_ids, assigned_program_ids)
      |> assign(:session_staffing_modal, nil)
      |> assign(:session, nil)
      # Regular assign (not stream): small bounded collection, needs Enum.find/filter, always fully replaced.
      |> assign(:participation_records, [])
      |> assign(:checkout_form_expanded, nil)
      |> assign(:checkout_forms, %{})
      |> assign(:absence_form_expanded, nil)
      |> assign(:absence_forms, %{})
      |> assign(:note_form_expanded, nil)
      |> assign(:note_forms, %{})
      |> assign(:revision_form_expanded, nil)
      |> assign(:revision_forms, %{})
      |> assign(:edit_form_expanded, nil)
      |> assign(:edit_forms, %{})
      |> assign(:provider_notes, %{})
      |> assign(:record_note_map, %{})
      |> assign(:session_form, nil)

    if connected?(socket) do
      # One topic for everything this provider does — attendance and session notes
      # alike. Notes used to arrive on their own registry-derived topics, which
      # carried every provider's notes, not just this one's.
      Phoenix.PubSub.subscribe(KlassHero.PubSub, Participation.provider_topic(provider_id))
    end

    {:ok, load_session_data(socket)}
  end

  @impl true
  def handle_event("check_in", %{"id" => record_id}, socket) do
    ParticipationLiveHandlers.check_in(socket, record_id, &load_session_data/1)
  end

  # No session id in the params: this page shows one session and already holds its
  # id, put there by the mount-time guard.
  @impl true
  def handle_event("start_session", _params, socket) do
    ParticipationLiveHandlers.start_session(socket, &load_session_data/1)
  end

  @impl true
  def handle_event("complete_session", _params, socket) do
    ParticipationLiveHandlers.complete_session(socket, &load_session_data/1)
  end

  # --- Session staffing panel (#782) ---------------------------------------
  #
  # Every event here reads the session id from the mount-time assign, never from
  # the client — same rule as the lifecycle writes above.

  @impl true
  def handle_event("manage_session_staffing", _params, socket) do
    case build_session_staffing_modal(socket) do
      {:ok, modal} ->
        {:noreply, assign(socket, :session_staffing_modal, modal)}

      {:error, :not_found} ->
        {:noreply, session_staffing_not_found(socket, "open", socket.assigns.session_id)}
    end
  end

  @impl true
  def handle_event("close_session_staffing", _params, socket) do
    {:noreply, assign(socket, :session_staffing_modal, nil)}
  end

  @impl true
  def handle_event("assign_session_staff", %{"add_staff" => %{"staff_id" => ""}}, socket) do
    {:noreply, put_flash(socket, :error, gettext("Pick a staff member to add."))}
  end

  def handle_event("assign_session_staff", %{"add_staff" => %{"staff_id" => staff_member_id}}, socket) do
    session_id = socket.assigns.session_id

    %{
      provider_id: socket.assigns.provider_id,
      session_id: session_id,
      staff_member_id: staff_member_id,
      assigned_by_user_id: socket.assigns.current_scope.user.id
    }
    |> Provider.assign_staff_to_session()
    |> case do
      {:ok, _assignment} ->
        {:noreply,
         socket
         |> refresh_session_staffing()
         |> put_flash(:info, gettext("Staff member added to this session."))}

      # The picker excludes them, so this is a stale panel (two tabs, back button)
      # rather than user error — re-read so the list stops offering them.
      {:error, :already_assigned} ->
        {:noreply,
         socket
         |> refresh_session_staffing()
         |> put_flash(:error, gettext("They are already working this session."))}

      {:error, :not_found} ->
        {:noreply, session_staffing_not_found(socket, "assign", staff_member_id)}
    end
  end

  @impl true
  def handle_event("remove_session_staff", %{"staff-id" => staff_member_id}, socket) do
    session_id = socket.assigns.session_id

    case Provider.unassign_staff_from_session(session_id, staff_member_id, socket.assigns.provider_id) do
      {:ok, _assignment} ->
        {:noreply,
         socket
         |> refresh_session_staffing()
         |> put_flash(:info, gettext("Staff member removed from this session."))}

      {:error, :cannot_unassign_lead} ->
        {:noreply,
         socket
         |> refresh_session_staffing()
         |> put_flash(
           :error,
           gettext("This person leads the session. Make someone else lead before removing them.")
         )}

      # The button is disabled for this case, so reaching it means a stale panel —
      # re-read so the disabled state catches up with what the context enforced.
      {:error, :cannot_empty_session} ->
        {:noreply,
         socket
         |> refresh_session_staffing()
         |> put_flash(
           :error,
           gettext(
             "A session needs at least one person. Use “Go back to the program's usual team” to drop this session's own roster."
           )
         )}

      # Already gone — a benign double-click or a second tab, not an error worth a
      # red flash. Re-read so the row disappears.
      {:error, :not_found} ->
        {:noreply, refresh_session_staffing(socket)}
    end
  end

  @impl true
  def handle_event("promote_session_lead", %{"staff-id" => staff_member_id}, socket) do
    session_id = socket.assigns.session_id

    case Provider.set_session_lead_instructor(session_id, staff_member_id, socket.assigns.provider_id) do
      {:ok, _assignment} ->
        {:noreply,
         socket
         |> refresh_session_staffing()
         |> put_flash(:info, gettext("Lead instructor for this session updated."))}

      {:error, :not_found} ->
        {:noreply, session_staffing_not_found(socket, "promote", staff_member_id)}
    end
  end

  @impl true
  def handle_event("revert_session_staffing", _params, socket) do
    session_id = socket.assigns.session_id

    case Provider.revert_session_to_program_roster(session_id, socket.assigns.provider_id) do
      {:ok, _count} ->
        {:noreply,
         socket
         |> refresh_session_staffing()
         |> put_flash(:info, gettext("This session is back on the program's usual team."))}

      {:error, :not_found} ->
        {:noreply, session_staffing_not_found(socket, "revert", session_id)}
    end
  end

  # --- Session editing (#1074) --------------------------------------------
  #
  # The session id comes from the socket, not the client, and
  # `Participation.update_session/3` authorizes it again regardless.

  @impl true
  def handle_event("edit_session", _params, socket) do
    form = socket.assigns.session |> SessionFormHandlers.form_from_session() |> to_form(as: :session)

    {:noreply, assign(socket, :session_form, form)}
  end

  @impl true
  def handle_event("cancel_edit_session", _params, socket) do
    {:noreply, assign(socket, :session_form, nil)}
  end

  @impl true
  def handle_event("validate_session", %{"session" => params}, socket) do
    {:noreply, assign(socket, :session_form, to_form(params, as: :session))}
  end

  @impl true
  def handle_event("save_session", %{"session" => params}, socket) do
    case SessionFormHandlers.submit_update(socket.assigns.current_scope, socket.assigns.session_id, params) do
      {:ok, _session} ->
        {:noreply,
         socket
         |> assign(:session_form, nil)
         |> put_flash(:info, gettext("Session updated"))
         |> load_session_data()}

      {:error, reason} ->
        if !SessionFormHandlers.user_correctable?(reason) do
          Logger.error(
            "[ParticipationLive.save_session] Failed to update session",
            session_id: socket.assigns.session_id,
            reason: inspect(reason),
            provider_id: socket.assigns.provider_id
          )
        end

        {:noreply, put_flash(socket, :error, SessionFormHandlers.humanize_error(reason))}
    end
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
  def handle_event("expand_absence_form", %{"id" => record_id}, socket) do
    {:noreply, expand_form(socket, record_id, "absence", "content", "", :absence_form_expanded, :absence_forms)}
  end

  @impl true
  def handle_event("cancel_absence", %{"id" => record_id}, socket) do
    {:noreply, cancel_form(socket, record_id, :absence_form_expanded, :absence_forms)}
  end

  @impl true
  def handle_event("update_absence_reason", %{"id" => record_id, "absence" => %{"content" => reason}}, socket) do
    {:noreply, update_form(socket, record_id, reason, "absence", "content", :absence_forms)}
  end

  @impl true
  def handle_event("confirm_absence", %{"id" => record_id, "absence" => params}, socket) do
    ParticipationLiveHandlers.mark_absent(socket, record_id, params, &load_session_data/1)
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
  def handle_event("expand_revision_form", %{"id" => note_id}, socket) do
    existing_note = Map.get(socket.assigns.provider_notes, note_id)
    initial = if existing_note, do: existing_note.content, else: ""

    {:noreply,
     expand_form(
       socket,
       note_id,
       "revision",
       "content",
       initial,
       :revision_form_expanded,
       :revision_forms
     )}
  end

  @impl true
  def handle_event("cancel_revision", %{"id" => note_id}, socket) do
    {:noreply, cancel_form(socket, note_id, :revision_form_expanded, :revision_forms)}
  end

  @impl true
  def handle_event("update_revision_content", %{"id" => note_id, "revision" => %{"content" => content}}, socket) do
    {:noreply, update_form(socket, note_id, content, "revision", "content", :revision_forms)}
  end

  @impl true
  def handle_event("submit_revision", %{"id" => note_id, "revision" => params}, socket) do
    content = Map.get(params, "content", "")

    case Participation.revise_session_note(socket.assigns.current_scope, %{
           note_id: note_id,
           content: content
         }) do
      {:ok, _note} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Note resubmitted for review"))
         |> assign(:revision_form_expanded, nil)
         |> assign(:revision_forms, Map.delete(socket.assigns.revision_forms, note_id))
         |> load_session_data()}

      {:error, :blank_content} ->
        {:noreply, put_flash(socket, :error, gettext("Note content cannot be blank"))}

      {:error, reason} ->
        Logger.error("[ParticipationLive.submit_revision] Failed",
          note_id: note_id,
          reason: inspect(reason)
        )

        {:noreply, put_flash(socket, :error, gettext("Failed to resubmit note"))}
    end
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
        Logger.error("[ParticipationLive.submit_edit] Failed",
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

  # Submitted adds a note, approved/rejected removes one — all three refresh.
  @impl true
  def handle_info(:session_notes_changed, socket) do
    {:noreply, load_session_data(socket)}
  end

  @impl true
  def handle_info(_message, socket) do
    # The provider-scoped topic also carries session-lifecycle messages this view
    # doesn't act on. Ignore them rather than crash on an unmatched message.
    {:noreply, socket}
  end

  defp load_session_data(socket) do
    session_id = socket.assigns.session_id

    case Participation.get_session_with_roster_enriched(session_id) do
      {:ok, session} ->
        # Ownership guard (IDOR): the session's program must belong to this provider,
        # else any provider could read another business's roster via a guessed id.
        # Mutation is guarded in the context as of ADR-0017 (#1353); this stays as
        # defence in depth and to keep a foreign roster off the screen entirely.
        if MapSet.member?(socket.assigns.assigned_program_ids, session.program_id) do
          socket
          |> assign(:session, session)
          |> assign(:participation_records, session.participation_records || [])
          |> assign(:session_error, nil)
          |> load_provider_notes()
        else
          Logger.warning(
            "[ParticipationLive] Unauthorized access to session",
            session_id: session_id,
            provider_id: socket.assigns.provider_id
          )

          socket
          |> put_flash(:error, gettext("You are not assigned to this program"))
          |> push_navigate(to: ~p"/provider/sessions")
        end

      {:error, :not_found} ->
        Logger.warning(
          "[ParticipationLive.load_session_data] Session not found",
          session_id: session_id
        )

        socket
        |> put_flash(:error, gettext("Session not found"))
        |> push_navigate(to: ~p"/provider/sessions")
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
          "[ParticipationLive.update_participation_record] Failed to refresh session",
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

    # Single batch query instead of N+1 per record.
    notes =
      Participation.list_session_notes_by_records_and_provider(record_ids, provider_id)

    notes_by_record =
      Map.new(notes, fn note -> {to_string(note.participation_record_id), note} end)

    notes_by_id = Map.new(notes, fn note -> {to_string(note.id), note} end)

    socket
    |> assign(:record_note_map, notes_by_record)
    |> assign(:provider_notes, notes_by_id)
  end

  # Two scoped facade reads joined by a presenter. `get_session_staffing_for_provider/2`
  # is the IDOR guard *and* the source of the override-vs-program fact the panel
  # renders — one call answers "may they see this?" and "where did this roster come
  # from?".
  defp build_session_staffing_modal(socket) do
    provider_id = socket.assigns.provider_id
    session_id = socket.assigns.session_id

    with {:ok, staffing} <- Provider.get_session_staffing_for_provider(provider_id, session_id) do
      lead_id = staffing.lead && staffing.lead.id

      members =
        session_id
        |> Provider.list_session_staff()
        |> ProgramStaffingPresenter.for_panel(lead_id)

      assignable =
        provider_id
        |> Provider.list_assignable_staff_for_session(session_id)
        |> ProgramStaffingPresenter.assignable_options()

      {:ok,
       %{
         session_label: session_label(socket),
         program_title: socket.assigns.session.program_name,
         overridden?: SessionStaffing.overridden?(staffing),
         members: members,
         assignable_options: assignable,
         # Rebuilt on every re-read, so the picker resets to its prompt after a
         # successful add instead of still naming the person now on the roster.
         add_form: to_form(%{"staff_id" => ""}, as: :add_staff)
       }}
    end
  end

  # Every mutation re-reads rather than patching the assign in place: the context
  # owns who works the session and whether that roster is its own.
  defp refresh_session_staffing(socket) do
    case build_session_staffing_modal(socket) do
      {:ok, modal} -> assign(socket, :session_staffing_modal, modal)
      {:error, :not_found} -> assign(socket, :session_staffing_modal, nil)
    end
  end

  defp session_label(socket) do
    Calendar.strftime(socket.assigns.session.session_date, "%a, %d %b")
  end

  defp session_staffing_not_found(socket, action, subject_id) do
    Logger.warning("[ParticipationLive] Session staffing #{action} for unknown or foreign target",
      session_id: subject_id,
      provider_id: socket.assigns.provider_id
    )

    socket
    |> assign(:session_staffing_modal, nil)
    |> put_flash(:error, gettext("That session could not be found."))
  end
end
