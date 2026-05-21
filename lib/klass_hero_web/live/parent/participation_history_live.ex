defmodule KlassHeroWeb.Parent.ParticipationHistoryLive do
  use KlassHeroWeb, :live_view

  alias KlassHero.Family
  alias KlassHero.Participation
  alias KlassHero.Shared.Domain.Events.DomainEvent
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
      |> assign(:children_ids, MapSet.new())
      # Uses stream for memory efficiency because:
      # - Potentially large, unbounded collection (all parent's history)
      # - Incremental updates (new check-ins prepended via PubSub)
      # - No need to enumerate in memory (LiveView handles rendering)
      |> stream(:participation_records, [])
      |> assign(:pending_notes, [])
      |> assign(:reject_form_expanded, nil)
      |> assign(:reject_forms, %{})

    if connected?(socket) do
      Phoenix.PubSub.subscribe(KlassHero.PubSub, "participation_record:child_checked_in")
      Phoenix.PubSub.subscribe(KlassHero.PubSub, "participation_record:child_checked_out")

      Phoenix.PubSub.subscribe(
        KlassHero.PubSub,
        "participation_record:participation_marked_absent"
      )

      Phoenix.PubSub.subscribe(KlassHero.PubSub, "behavioral_note:behavioral_note_submitted")
    end

    {:ok, load_participation_history(socket)}
  end

  # Behavioral note review event handlers

  @impl true
  def handle_event("approve_note", %{"id" => note_id}, socket) do
    case Participation.review_behavioral_note(%{
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

    case Participation.review_behavioral_note(%{
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

  # PubSub event handler for participation record events
  @impl true
  def handle_info(
        {:domain_event, %DomainEvent{event_type: event_type, aggregate_id: record_id, payload: %{child_id: child_id}}},
        socket
      )
      when event_type in [:child_checked_in, :child_checked_out, :participation_marked_absent] do
    socket =
      if child_belongs_to_parent?(child_id, socket) do
        # New check-ins are prepended (at: 0), updates replace in-place
        opts = if event_type == :child_checked_in, do: [at: 0], else: []
        load_and_stream_record(socket, record_id, opts)
      else
        socket
      end

    {:noreply, socket}
  end

  # PubSub handler for new behavioral note — refresh pending notes if child belongs to parent
  @impl true
  def handle_info(
        {:domain_event, %DomainEvent{event_type: :behavioral_note_submitted, payload: %{child_id: child_id}}},
        socket
      ) do
    socket =
      if child_belongs_to_parent?(child_id, socket) do
        load_pending_notes(socket)
      else
        socket
      end

    {:noreply, socket}
  end

  # Private helper functions

  defp child_belongs_to_parent?(child_id, socket) do
    MapSet.member?(socket.assigns.children_ids, child_id)
  end

  defp load_participation_history(socket) do
    parent_id = socket.assigns.parent_id

    if parent_id do
      children = Family.get_children(parent_id)
      child_ids = Enum.map(children, & &1.id)

      case Participation.get_participation_history(%{child_ids: child_ids}) do
        {:ok, records} -> apply_history(socket, children, records)
        {:error, reason} -> handle_history_error(socket, parent_id, reason)
      end
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

    # Derive children_ids from already-fetched children list to avoid a redundant DB query.
    children_ids = MapSet.new(children, & &1.id)

    enriched_records =
      Enum.map(participation_records, &enrich_history_record(&1, child_names_map))

    socket
    |> assign(:child_names_map, child_names_map)
    |> assign(:children_ids, children_ids)
    |> stream(:participation_records, enriched_records, reset: true)
    |> assign(:participation_error, nil)
    |> load_pending_notes()
  end

  defp handle_history_error(socket, parent_id, reason) do
    Logger.error(
      "[ParticipationHistoryLive.load_participation_history] Failed to load history",
      parent_id: parent_id,
      reason: inspect(reason)
    )

    socket
    |> stream(:participation_records, [], reset: true)
    |> assign(:participation_error, gettext("Failed to load participation history"))
  end

  defp load_pending_notes(socket) do
    parent_id = socket.assigns.parent_id

    case Participation.list_pending_behavioral_notes(parent_id) do
      {:ok, notes} ->
        assign(socket, :pending_notes, notes)

      {:error, reason} ->
        Logger.error("[ParticipationHistoryLive.load_pending_notes] Failed to load notes",
          parent_id: parent_id,
          reason: inspect(reason)
        )

        put_flash(socket, :error, gettext("Failed to load pending notes"))
    end
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

    # Trigger: record is a struct — Map.put on structs bypasses struct enforcement
    # Why: convert to plain map so presentation fields can be safely merged
    # Outcome: template gets a flat map with all struct fields + enrichment keys
    Map.from_struct(record)
    |> Map.merge(%{
      child_first_name: child_info.first_name,
      child_last_name: child_info.last_name,
      program_name: Map.get(record, :program_name),
      session_date: Map.get(record, :session_date),
      session_start_time: Map.get(record, :session_start_time)
    })
  end

  # Template helper functions

  defp format_date(nil), do: "N/A"
  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%B %d, %Y")

  defp format_time(%Time{} = time), do: Calendar.strftime(time, "%I:%M %p")

  defp format_datetime(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%B %d, %Y at %I:%M %p")
  end
end
