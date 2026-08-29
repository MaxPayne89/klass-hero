defmodule KlassHeroWeb.Provider.ScheduleLive do
  @moduledoc """
  The provider's Schedule — their sessions on a day, week or month calendar.

  Replaces the My Sessions list (#1501), which showed one date at a time and
  could not answer "what does next week look like".

  ## The URL is the state

  `view` and `date` live in the query string, and every control patches rather
  than assigning. So a refresh keeps the period, the back button steps through
  the periods visited, and a link to a particular week is shareable. Both params
  are coerced rather than validated (`CalendarRange` gets a real `Date` or the
  page falls back to today) — they arrive from the address bar, where a person
  can type anything.

  ## One range, drawn and queried

  `CalendarRange.range_for/2` decides which days are on screen, and the same
  range bounds the query. A month grid pads to whole weeks, so the fetch covers
  that padding too — otherwise the leading and trailing cells would render empty
  while sessions sat on those days.
  """
  use KlassHeroWeb, :live_view

  import KlassHeroWeb.ProviderComponents, only: [calendar_grid: 1]

  alias KlassHero.Participation
  alias KlassHeroWeb.Helpers.CalendarRange
  alias KlassHeroWeb.Theme

  @view_modes ~w(day week month)a

  @impl true
  def mount(_params, _session, socket) do
    provider_id = socket.assigns.current_scope.provider.id

    if connected?(socket) do
      Phoenix.PubSub.subscribe(KlassHero.PubSub, Participation.provider_topic(provider_id))
    end

    {:ok,
     socket
     |> assign(:page_title, gettext("Schedule"))
     |> assign(:active_nav, :calendar)
     |> assign(:provider_id, provider_id)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    view_mode = parse_view_mode(params["view"])
    focus_date = parse_date(params["date"])

    {:noreply,
     socket
     |> assign(:view_mode, view_mode)
     |> assign(:focus_date, focus_date)
     |> assign(:range, CalendarRange.range_for(view_mode, focus_date))
     |> assign(:period_label, period_label(view_mode, focus_date))
     |> load_sessions()}
  end

  # Names the period the way the heading needs it: the day itself, the week by
  # its Monday and Sunday, the month by its name.
  defp period_label(:day, date), do: Calendar.strftime(date, "%A, %-d %B %Y")

  defp period_label(:week, date) do
    range = CalendarRange.range_for(:week, date)

    "#{Calendar.strftime(range.first, "%-d %b")} – #{Calendar.strftime(range.last, "%-d %b %Y")}"
  end

  defp period_label(:month, date), do: Calendar.strftime(date, "%B %Y")

  @impl true
  def handle_event("prev_period", _params, socket) do
    {:noreply, patch_to(socket, CalendarRange.step(socket.assigns.view_mode, socket.assigns.focus_date, -1))}
  end

  @impl true
  def handle_event("next_period", _params, socket) do
    {:noreply, patch_to(socket, CalendarRange.step(socket.assigns.view_mode, socket.assigns.focus_date, 1))}
  end

  @impl true
  def handle_event("today", _params, socket) do
    {:noreply, patch_to(socket, Date.utc_today())}
  end

  @impl true
  def handle_event("set_view_mode", %{"mode" => mode}, socket) do
    {:noreply, patch_to(socket, socket.assigns.focus_date, parse_view_mode(mode))}
  end

  @impl true
  def handle_event("change_date", %{"date" => date}, socket) do
    {:noreply, patch_to(socket, parse_date(date))}
  end

  # A session write anywhere in this provider's world can land on the period
  # being viewed, and the event does not say which day it touched — so re-read
  # the range rather than trying to patch one cell.
  @impl true
  def handle_info({:session_changed, _session_id}, socket), do: {:noreply, load_sessions(socket)}

  @impl true
  def handle_info({:sessions_generated, _program_id}, socket), do: {:noreply, load_sessions(socket)}

  @impl true
  def handle_info({:attendance_changed, _payload}, socket), do: {:noreply, load_sessions(socket)}

  # The provider topic carries every participation message for this provider, not
  # only the ones this view renders. Without this an unmatched message is a
  # FunctionClauseError that takes the LiveView down.
  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # Iron Law 1: nothing queries in the disconnected mount. assign_async runs the
  # fetch off-process and gives the template a real failed state, which a bare
  # `loading?` boolean cannot.
  defp load_sessions(socket) do
    %{provider_id: provider_id, range: range} = socket.assigns

    assign_async(socket, :sessions, fn ->
      summaries =
        Participation.list_session_summaries(%{
          provider_id: provider_id,
          date_from: range.first,
          date_to: range.last
        })

      {:ok, %{sessions: Enum.group_by(summaries, & &1.session_date)}}
    end)
  end

  defp patch_to(socket, %Date{} = date, view_mode \\ nil) do
    view_mode = view_mode || socket.assigns.view_mode

    push_patch(socket, to: ~p"/provider/schedule?view=#{view_mode}&date=#{Date.to_iso8601(date)}")
  end

  defp parse_view_mode(mode) when is_binary(mode) do
    Enum.find(@view_modes, :month, &(Atom.to_string(&1) == mode))
  end

  defp parse_view_mode(_mode), do: :month

  defp parse_date(date) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, parsed} -> parsed
      {:error, _reason} -> Date.utc_today()
    end
  end

  defp parse_date(_date), do: Date.utc_today()
end
