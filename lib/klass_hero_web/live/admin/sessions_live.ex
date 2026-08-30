defmodule KlassHeroWeb.Admin.SessionsLive do
  @moduledoc """
  Admin dashboard for participation sessions.

  Unified view with searchable provider/program dropdowns,
  date range, and status filter. All filters apply live.
  """

  use KlassHeroWeb, :live_view

  alias KlassHero.Admin.Queries
  alias KlassHero.Participation
  alias KlassHeroWeb.Admin.Components.SearchableSelect
  alias KlassHeroWeb.Theme

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()
    all_providers = Queries.list_providers_for_select()
    all_programs = Queries.list_programs_for_select()

    {:ok,
     socket
     |> assign(:fluid?, false)
     |> assign(:live_resource, nil)
     |> assign(:page_title, gettext("Sessions"))
     |> assign(:session_statuses, Participation.session_statuses())
     |> assign(:all_providers, all_providers)
     |> assign(:all_programs, all_programs)
     |> assign(:filtered_programs, all_programs)
     |> assign(:selected_provider, nil)
     |> assign(:selected_program, nil)
     |> assign(:date_from, today)
     |> assign(:date_to, today)
     |> assign(:selected_status, nil)}
  end

  # @current_url is assigned by Backpex.InitAssigns' handle_params hook, attached
  # in the :admin_custom live_session.
  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    load_sessions(socket)
  end

  # Non-UUID strings cause Ecto.Query.CastError — redirect instead of crashing.
  defp apply_action(socket, :show, %{"id" => id}) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        case Participation.get_session_with_roster_enriched(uuid) do
          {:ok, session} ->
            socket
            |> assign(:session, session)
            |> assign(:editing_record_id, nil)
            |> assign(:correction_form, nil)

          {:error, :not_found} ->
            socket
            |> put_flash(:error, gettext("Session not found"))
            |> push_navigate(to: ~p"/admin/sessions")
        end

      :error ->
        socket
        |> put_flash(:error, gettext("Session not found"))
        |> push_navigate(to: ~p"/admin/sessions")
    end
  end

  @impl true
  def handle_info({:select, "provider_id", selected}, socket) do
    # Selecting a provider cascades to narrow program options in-memory; stale program selection is cleared.
    filtered_programs =
      case selected do
        nil ->
          socket.assigns.all_programs

        %{id: provider_id} ->
          Enum.filter(socket.assigns.all_programs, &(&1.provider_id == provider_id))
      end

    selected_program =
      case socket.assigns.selected_program do
        nil ->
          nil

        %{id: program_id} ->
          if Enum.any?(filtered_programs, &(&1.id == program_id)) do
            socket.assigns.selected_program
          end
      end

    socket
    |> assign(:selected_provider, selected)
    |> assign(:filtered_programs, filtered_programs)
    |> assign(:selected_program, selected_program)
    |> load_sessions()
    |> then(&{:noreply, &1})
  end

  @impl true
  def handle_info({:select, "program_id", selected}, socket) do
    socket
    |> assign(:selected_program, selected)
    |> load_sessions()
    |> then(&{:noreply, &1})
  end

  @impl true
  def handle_event("filter_change", params, socket) do
    date_from = parse_date(params["date_from"], socket.assigns.date_from)
    date_to = parse_date(params["date_to"], socket.assigns.date_to)
    selected_status = parse_status(params["status"])

    socket
    |> assign(:selected_status, selected_status)
    |> apply_date_range(date_from, date_to)
    |> load_sessions()
    |> then(&{:noreply, &1})
  end

  @impl true
  def handle_event("reset_dates", _params, socket) do
    today = Date.utc_today()

    socket
    |> assign(:date_from, today)
    |> assign(:date_to, today)
    |> load_sessions()
    |> then(&{:noreply, &1})
  end

  @impl true
  def handle_event("open_correction", %{"record-id" => record_id}, socket) do
    {:noreply,
     socket
     |> assign(:editing_record_id, record_id)
     |> assign(:correction_form, to_form(%{"reason" => ""}, as: :correction))}
  end

  @impl true
  def handle_event("cancel_correction", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_record_id, nil)
     |> assign(:correction_form, nil)}
  end

  @impl true
  def handle_event("save_correction", %{"correction" => correction_params}, socket) do
    record_id = socket.assigns.editing_record_id

    base_params =
      %{reason: correction_params["reason"]}
      |> maybe_put_status(correction_params)

    with {:ok, params} <-
           maybe_put_time(base_params, :check_in_at, correction_params["check_in_at"]),
         {:ok, params} <- maybe_put_time(params, :check_out_at, correction_params["check_out_at"]),
         {:ok, _corrected} <-
           Participation.correct_attendance(socket.assigns.current_scope, record_id, params),
         {:ok, session} <-
           Participation.get_session_with_roster_enriched(socket.assigns.session.id) do
      {:noreply,
       socket
       |> assign(:session, session)
       |> assign(:editing_record_id, nil)
       |> assign(:correction_form, nil)
       |> put_flash(:info, gettext("Attendance corrected successfully"))}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_message(reason))}
    end
  end

  defp load_sessions(socket) do
    filters = build_filters(socket.assigns)
    sessions = Participation.list_session_summaries(filters)
    stream(socket, :sessions, sessions, reset: true)
  end

  defp build_filters(assigns) do
    %{}
    |> maybe_add_filter(:provider_id, get_in(assigns, [:selected_provider, :id]))
    |> maybe_add_filter(:program_id, get_in(assigns, [:selected_program, :id]))
    |> maybe_add_filter(:status, assigns.selected_status)
    |> maybe_add_date_range(assigns.date_from, assigns.date_to)
  end

  defp maybe_add_filter(filters, _key, nil), do: filters
  defp maybe_add_filter(filters, key, value), do: Map.put(filters, key, value)

  defp maybe_add_date_range(filters, %Date{} = from, %Date{} = to) when from == to, do: Map.put(filters, :date, from)

  defp maybe_add_date_range(filters, %Date{} = from, %Date{} = to),
    do: Map.merge(filters, %{date_from: from, date_to: to})

  defp maybe_add_date_range(filters, _, _), do: filters

  # These two dates come from free-form date inputs, so the pair can be any span
  # a person can click. `Participation.list_session_summaries/1` raises past a
  # year rather than loading the table, which is right for the calendar that
  # derives its range but would be a crash here. Clamp and say so: narrowing in
  # silence would show a subset of what was asked for and look like the answer.
  # Admin's range comes from two free-form date inputs, so it can exceed what the
  # context serves. Clamping here keeps the context's raise what it is meant to be:
  # a programmer error, never a user's click. Reading the bound from the context,
  # in the context's own unit, is what stops the two drifting apart.
  defp apply_date_range(socket, %Date{} = from, %Date{} = to) do
    max_days = Participation.max_session_span_days()

    if Date.diff(to, from) + 1 > max_days do
      clamped = Date.add(from, max_days - 1)

      socket
      |> assign(:date_from, from)
      |> assign(:date_to, clamped)
      |> put_flash(
        :info,
        gettext("Showing the first year from %{from}. Narrow the range to see later sessions.",
          from: Date.to_iso8601(from)
        )
      )
    else
      socket
      |> assign(:date_from, from)
      |> assign(:date_to, to)
    end
  end

  defp parse_date("", fallback), do: fallback
  defp parse_date(nil, fallback), do: fallback

  defp parse_date(date_string, fallback) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      _ -> fallback
    end
  end

  @session_status_strings Enum.map(Participation.session_statuses(), &to_string/1)
  @record_status_strings Enum.map(Participation.record_statuses(), &to_string/1)

  defp parse_status(""), do: nil
  defp parse_status(nil), do: nil
  defp parse_status(s) when s in @session_status_strings, do: String.to_existing_atom(s)
  defp parse_status(_), do: nil

  defp maybe_put_status(params, %{"status" => ""}), do: params

  defp maybe_put_status(params, %{"status" => s}) when s in @record_status_strings,
    do: Map.put(params, :status, String.to_existing_atom(s))

  defp maybe_put_status(params, _), do: params

  defp maybe_put_time(params, _key, nil), do: {:ok, params}
  defp maybe_put_time(params, _key, ""), do: {:ok, params}

  defp maybe_put_time(params, key, time_string) do
    normalized = normalize_datetime_local(time_string)

    case NaiveDateTime.from_iso8601(normalized) do
      {:ok, ndt} -> {:ok, Map.put(params, key, DateTime.from_naive!(ndt, "Etc/UTC"))}
      _ -> {:error, :invalid_time}
    end
  end

  # datetime-local inputs omit seconds; NaiveDateTime.from_iso8601/1 requires them.
  defp normalize_datetime_local(s) when byte_size(s) == 16, do: s <> ":00"
  defp normalize_datetime_local(s), do: s

  defp error_message(:reason_required), do: gettext("A reason is required for corrections")
  defp error_message(:no_changes), do: gettext("No changes detected")
  defp error_message(:not_found), do: gettext("Record not found")

  defp error_message(:stale_data), do: gettext("Record was modified by someone else. Please refresh.")

  defp error_message(:check_out_requires_check_in), do: gettext("Cannot check out without a check-in")

  defp error_message(:check_in_must_precede_check_out), do: gettext("Check-in time must be before check-out time")

  defp error_message(:invalid_time), do: gettext("Invalid time format")

  defp error_message(_), do: gettext("An error occurred")

  defp status_badge_class(:scheduled), do: "badge-info"
  defp status_badge_class(:in_progress), do: "badge-success"
  defp status_badge_class(:completed), do: "badge-secondary"
  defp status_badge_class(:cancelled), do: "badge-error"
  defp status_badge_class(_), do: ""

  defp record_status_class(:registered), do: "badge-ghost"
  defp record_status_class(:checked_in), do: "badge-success"
  defp record_status_class(:checked_out), do: "badge-secondary"
  defp record_status_class(:absent), do: "badge-error"
  defp record_status_class(_), do: ""

  defp humanize_status(:in_progress), do: gettext("In Progress")
  defp humanize_status(:checked_in), do: gettext("Checked In")
  defp humanize_status(:checked_out), do: gettext("Checked Out")
  defp humanize_status(status), do: status |> to_string() |> String.capitalize()

  defp format_time(nil), do: "—"
  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M")

  defp format_datetime_local(nil), do: ""
  defp format_datetime_local(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%dT%H:%M")

  defp note_badge(record) do
    notes = Map.get(record, :session_notes, [])

    cond do
      notes == [] ->
        "—"

      Enum.any?(notes, &(&1.status == :approved)) ->
        gettext("Approved")

      Enum.any?(notes, &(&1.status == :pending_approval)) ->
        gettext("Pending")

      true ->
        "—"
    end
  end
end
