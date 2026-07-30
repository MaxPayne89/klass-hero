defmodule KlassHeroWeb.Parent.ParticipationHistoryLive do
  use KlassHeroWeb, :live_view

  alias KlassHero.Family
  alias KlassHero.Participation
  alias KlassHeroWeb.Theme

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    parent_id = socket.assigns.current_scope.parent.id

    socket =
      socket
      |> assign(:page_title, gettext("Participation History"))
      |> assign(:active_nav, :participation)
      |> assign(:parent_id, parent_id)
      |> assign(:child_names_map, %{})
      |> stream(:participation_records, [])
      |> assign(:pending_notes, [])
      |> assign(:reject_form_expanded, nil)
      |> assign(:reject_forms, %{})

    if connected?(socket) do
      # Subscribe per child to child-scoped topics (#1121) so this LiveView only
      # receives its own children's attendance + session-note events — no generic
      # firehose, no handle_info membership filter. The subscription set is fixed at
      # mount: a child added mid-session isn't streamed until the next remount.
      for child_id <- Family.get_child_ids_for_parent(parent_id),
          do: Phoenix.PubSub.subscribe(KlassHero.PubSub, Participation.child_topic(child_id))
    end

    {:ok, load_participation_history(socket)}
  end

  @impl true
  def handle_event("approve_note", %{"id" => note_id}, socket) do
    case Participation.review_session_note(%{
           note_id: note_id,
           parent_id: socket.assigns.parent_id,
           decision: :approve
         }) do
      {:ok, _note} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Note approved"))
         |> load_pending_notes()}

      {:error, reason} ->
        Logger.error("[ParticipationHistoryLive.approve_note] Failed",
          note_id: note_id,
          reason: inspect(reason)
        )

        {:noreply, put_flash(socket, :error, gettext("Failed to approve note"))}
    end
  end

  @impl true
  def handle_event("expand_reject_form", %{"id" => note_id}, socket) do
    form = to_form(%{"reason" => ""}, as: "reject")

    socket =
      socket
      |> assign(:reject_form_expanded, note_id)
      |> assign(:reject_forms, Map.put(socket.assigns.reject_forms, note_id, form))

    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_reject", %{"id" => note_id}, socket) do
    socket =
      socket
      |> assign(:reject_form_expanded, nil)
      |> assign(:reject_forms, Map.delete(socket.assigns.reject_forms, note_id))

    {:noreply, socket}
  end

  @impl true
  def handle_event("reject_note", %{"id" => note_id, "reject" => params}, socket) do
    reason = Map.get(params, "reason")
    reason = if reason != "", do: reason

    case Participation.review_session_note(%{
           note_id: note_id,
           parent_id: socket.assigns.parent_id,
           decision: :reject,
           reason: reason
         }) do
      {:ok, _note} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Note rejected"))
         |> assign(:reject_form_expanded, nil)
         |> assign(:reject_forms, Map.delete(socket.assigns.reject_forms, note_id))
         |> load_pending_notes()}

      {:error, reason} ->
        Logger.error("[ParticipationHistoryLive.reject_note] Failed",
          note_id: note_id,
          reason: inspect(reason)
        )

        {:noreply, put_flash(socket, :error, gettext("Failed to reject note"))}
    end
  end

  # Ownership is guaranteed by the child-scoped subscription (#1121) — we only
  # receive messages for this parent's children, so no membership check is needed.
  # A check-in is the only kind that puts a record at the top of the list.
  @impl true
  def handle_info({:attendance_changed, %{record_id: record_id, kind: kind}}, socket) do
    opts = if kind == :checked_in, do: [at: 0], else: []
    {:noreply, load_and_stream_record(socket, record_id, opts)}
  end

  # Any session-note change refreshes the pending list — submitted adds one,
  # approved/rejected removes one (e.g. reviewed from another device/tab).
  @impl true
  def handle_info(:session_notes_changed, socket) do
    {:noreply, load_pending_notes(socket)}
  end

  # The child topic carries anything scoped to this child. Ignore the messages with
  # no display effect here rather than crashing on an unmatched one (a new
  # child-scoped message must not break the page).
  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  defp load_participation_history(socket) do
    parent_id = socket.assigns.parent_id

    if parent_id do
      children = Family.get_children(parent_id)
      child_ids = Enum.map(children, & &1.id)

      {:ok, records} = Participation.get_participation_history(%{child_ids: child_ids})
      apply_history(socket, children, records)
    else
      Logger.warning("[ParticipationHistoryLive.load_participation_history] No parent_id available")

      socket
      |> stream(:participation_records, [], reset: true)
      |> assign(:participation_error, gettext("Failed to load participation history"))
    end
  end

  defp apply_history(socket, children, participation_records) do
    child_names_map =
      Map.new(children, fn child ->
        {child.id, %{first_name: child.first_name, last_name: child.last_name}}
      end)

    enriched_records =
      Enum.map(participation_records, &enrich_history_record(&1, child_names_map))

    socket
    |> assign(:child_names_map, child_names_map)
    |> stream(:participation_records, enriched_records, reset: true)
    |> assign(:participation_error, nil)
    |> load_pending_notes()
  end

  defp load_pending_notes(socket) do
    {:ok, notes} = Participation.list_pending_session_notes(socket.assigns.parent_id)
    assign(socket, :pending_notes, notes)
  end

  defp load_and_stream_record(socket, record_id, opts) do
    case Participation.get_participation_record(record_id) do
      {:ok, record} ->
        enriched = enrich_history_record(record, socket.assigns.child_names_map)
        stream_insert(socket, :participation_records, enriched, opts)

      {:error, reason} ->
        Logger.error(
          "[ParticipationHistoryLive] Failed to load record",
          record_id: record_id,
          reason: inspect(reason)
        )

        socket
    end
  end

  defp enrich_history_record(record, child_names_map) do
    child_info =
      Map.get(child_names_map, record.child_id, %{first_name: "Unknown", last_name: "Child"})

    # Convert struct to plain map so presentation fields can be safely merged.
    Map.from_struct(record)
    |> Map.merge(%{
      child_first_name: child_info.first_name,
      child_last_name: child_info.last_name,
      program_name: Map.get(record, :program_name),
      session_date: Map.get(record, :session_date),
      session_start_time: Map.get(record, :session_start_time)
    })
  end

  defp format_date(nil), do: "N/A"
  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%B %d, %Y")

  defp format_time(%Time{} = time), do: Calendar.strftime(time, "%I:%M %p")

  defp format_datetime(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%B %d, %Y at %I:%M %p")
  end
end
