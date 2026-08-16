defmodule KlassHeroWeb.Provider.ParticipationLive do
  use KlassHeroWeb, :live_view

  import KlassHeroWeb.Helpers.ParticipationEditHelpers,
    only: [
      expand_form: 7,
      cancel_form: 4,
      update_form: 6,
      find_participation_record: 2
    ]

  alias KlassHero.Participation
  alias KlassHero.ProgramCatalog
  alias KlassHeroWeb.Helpers.ParticipationEditHelpers
  alias KlassHeroWeb.Helpers.ParticipationLiveHandlers
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
      |> assign(:session, nil)
      # Regular assign (not stream): small bounded collection, needs Enum.find/filter, always fully replaced.
      |> assign(:participation_records, [])
      |> assign(:checkout_form_expanded, nil)
      |> assign(:checkout_forms, %{})
      |> assign(:note_form_expanded, nil)
      |> assign(:note_forms, %{})
      |> assign(:revision_form_expanded, nil)
      |> assign(:revision_forms, %{})
      |> assign(:edit_form_expanded, nil)
      |> assign(:edit_forms, %{})
      |> assign(:provider_notes, %{})
      |> assign(:record_note_map, %{})

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

    case Participation.revise_session_note(%{
           note_id: note_id,
           provider_id: socket.assigns.provider_id,
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
end
