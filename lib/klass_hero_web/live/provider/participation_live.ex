defmodule KlassHeroWeb.Provider.ParticipationLive do
  use KlassHeroWeb, :live_view

  alias KlassHero.Participation
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHeroWeb.Helpers.ParticipationEditHelpers
  alias KlassHeroWeb.Theme

  require Logger

  @impl true
  def mount(%{"session_id" => session_id}, _session, socket) do
    provider_id = socket.assigns.current_scope.provider.id

    socket =
      socket
      |> assign(:page_title, gettext("Manage Participation"))
      |> assign(:session_id, session_id)
      |> assign(:provider_id, provider_id)
      |> assign(:session, nil)
      # Uses regular assign (not stream) because:
      # - Small, bounded collection (records for single session)
      # - Need to filter/search records (Enum.find, Enum.filter)
      # - Full replacement on updates (no incremental changes)
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
      Phoenix.PubSub.subscribe(KlassHero.PubSub, "participation_record:child_checked_in")
      Phoenix.PubSub.subscribe(KlassHero.PubSub, "participation_record:child_checked_out")

      Phoenix.PubSub.subscribe(
        KlassHero.PubSub,
        "participation_record:participation_marked_absent"
      )

      Phoenix.PubSub.subscribe(KlassHero.PubSub, "behavioral_note:behavioral_note_submitted")
      Phoenix.PubSub.subscribe(KlassHero.PubSub, "behavioral_note:behavioral_note_approved")
      Phoenix.PubSub.subscribe(KlassHero.PubSub, "behavioral_note:behavioral_note_rejected")
    end

    {:ok, load_session_data(socket)}
  end

  @impl true
  def handle_event("check_in", %{"id" => record_id}, socket) do
    record = find_participation_record(socket, record_id)

    case record do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Record not found"))}

      record ->
        case Participation.record_check_in(%{
               record_id: record.id,
               checked_in_by: socket.assigns.current_scope.user.id
             }) do
          {:ok, _record} ->
            {:noreply,
             socket
             |> put_flash(:info, gettext("Child checked in successfully"))
             |> load_session_data()}

          {:error, reason} ->
            Logger.error(
              "[ParticipationLive.check_in] Failed to check in",
              record_id: record_id,
              child_id: record.child_id,
              reason: inspect(reason)
            )

            {:noreply,
             put_flash(
               socket,
               :error,
               gettext("Failed to check in: %{reason}", reason: inspect(reason))
             )}
        end
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
    record = find_participation_record(socket, record_id)
    notes = Map.get(params, "notes")

    case record do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Record not found"))}

      record ->
        case Participation.record_check_out(%{
               record_id: record.id,
               checked_out_by: socket.assigns.current_scope.user.id,
               notes: notes
             }) do
          {:ok, _record} ->
            {:noreply,
             socket
             |> put_flash(:info, gettext("Child checked out successfully"))
             |> assign(:checkout_form_expanded, nil)
             |> assign(:checkout_forms, Map.delete(socket.assigns.checkout_forms, record_id))
             |> load_session_data()}

          {:error, reason} ->
            Logger.error(
              "[ParticipationLive.confirm_checkout] Failed to check out",
              record_id: record_id,
              child_id: record.child_id,
              reason: inspect(reason)
            )

            {:noreply,
             put_flash(
               socket,
               :error,
               gettext("Failed to check out: %{reason}", reason: inspect(reason))
             )}
        end
    end
  end

  # Behavioral note form handlers

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
    case find_participation_record(socket, record_id) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Record not found"))}

      _record ->
        content = Map.get(params, "content", "")

        case Participation.submit_behavioral_note(%{
               participation_record_id: record_id,
               provider_id: socket.assigns.provider_id,
               content: content
             }) do
          {:ok, _note} ->
            {:noreply,
             socket
             |> put_flash(:info, gettext("Behavioral note submitted for review"))
             |> assign(:note_form_expanded, nil)
             |> assign(:note_forms, Map.delete(socket.assigns.note_forms, record_id))
             |> load_session_data()}

          {:error, :blank_content} ->
            {:noreply, put_flash(socket, :error, gettext("Note content cannot be blank"))}

          {:error, :duplicate_note} ->
            {:noreply, put_flash(socket, :error, gettext("You already submitted a note for this record"))}

          {:error, reason} ->
            Logger.error("[ParticipationLive.submit_note] Failed",
              record_id: record_id,
              reason: inspect(reason)
            )

            {:noreply, put_flash(socket, :error, gettext("Failed to submit note"))}
        end
    end
  end

  # Revision form handlers

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

    case Participation.revise_behavioral_note(%{
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
         {:ok, correction} <- ParticipationEditHelpers.build_edit_correction(record, params, :provider),
         {:ok, _} <- Participation.correct_attendance(correction) do
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

  # PubSub event handler for participation record events
  @impl true
  def handle_info({:domain_event, %DomainEvent{event_type: event_type, aggregate_id: record_id}}, socket)
      when event_type in [:child_checked_in, :child_checked_out, :participation_marked_absent] do
    {:noreply, update_participation_record(socket, record_id)}
  end

  # PubSub handler for behavioral note events — reload session + provider notes
  @impl true
  def handle_info({:domain_event, %DomainEvent{event_type: event_type}}, socket)
      when event_type in [:behavioral_note_submitted, :behavioral_note_approved, :behavioral_note_rejected] do
    {:noreply, load_session_data(socket)}
  end

  # Form lifecycle helpers — parameterized expand/cancel/update for all form types

  defp expand_form(socket, id, form_name, field, initial_value, expanded_key, forms_key) do
    form = to_form(%{field => initial_value}, as: form_name)

    socket
    |> assign(expanded_key, id)
    |> assign(forms_key, Map.put(Map.get(socket.assigns, forms_key), id, form))
  end

  defp cancel_form(socket, id, expanded_key, forms_key) do
    socket
    |> assign(expanded_key, nil)
    |> assign(forms_key, Map.delete(Map.get(socket.assigns, forms_key), id))
  end

  defp update_form(socket, id, value, form_name, field, forms_key) do
    updated_form = to_form(%{field => value}, as: form_name)
    assign(socket, forms_key, Map.put(Map.get(socket.assigns, forms_key), id, updated_form))
  end

  # Private helper functions

  defp load_session_data(socket) do
    session_id = socket.assigns.session_id

    case Participation.get_session_with_roster_enriched(session_id) do
      {:ok, session} ->
        socket
        |> assign(:session, session)
        |> assign(:participation_records, session.participation_records || [])
        |> assign(:session_error, nil)
        |> load_provider_notes()

      {:error, :not_found} ->
        Logger.warning(
          "[ParticipationLive.load_session_data] Session not found",
          session_id: session_id
        )

        socket
        |> put_flash(:error, gettext("Session not found"))
        |> push_navigate(to: ~p"/provider/sessions")

      {:error, reason} ->
        Logger.error(
          "[ParticipationLive.load_session_data] Failed to load session data",
          session_id: session_id,
          reason: inspect(reason)
        )

        socket
        |> assign(:session_error, gettext("Failed to load session data"))
        |> put_flash(:error, gettext("Failed to load session data"))
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

    # Trigger: batch-fetch this provider's notes for all participation records
    # Why: single query instead of N+1 per record
    # Outcome: provider_notes map keyed by note.id, record_note_map keyed by record.id
    notes =
      Participation.list_behavioral_notes_by_records_and_provider(record_ids, provider_id)

    notes_by_record =
      Map.new(notes, fn note -> {to_string(note.participation_record_id), note} end)

    notes_by_id = Map.new(notes, fn note -> {to_string(note.id), note} end)

    socket
    |> assign(:record_note_map, notes_by_record)
    |> assign(:provider_notes, notes_by_id)
  end

  defp find_participation_record(socket, record_id) do
    Enum.find(socket.assigns.participation_records, fn record ->
      to_string(record.id) == record_id
    end)
  end
end
