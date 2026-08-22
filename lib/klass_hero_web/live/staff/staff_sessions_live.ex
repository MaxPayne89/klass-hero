defmodule KlassHeroWeb.Staff.StaffSessionsLive do
  use KlassHeroWeb, :live_view

  alias KlassHero.Participation
  alias KlassHero.Provider
  alias KlassHero.Provider.ReadModels.SessionStaffing
  alias KlassHeroWeb.Helpers.ParticipationLiveHandlers
  alias KlassHeroWeb.Helpers.StaffLiveHelpers
  alias KlassHeroWeb.Theme

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    staff_member = socket.assigns.current_scope.staff_member
    provider_id = staff_member.provider_id
    selected_date = Date.utc_today()

    socket =
      socket
      |> assign(:page_title, gettext("My Sessions"))
      # Names every program the provider runs, not only the ones this staff member
      # is assigned to. A session reaches the stream on its own staffing (#783), so
      # deriving titles from program assignments would leave an overridden session
      # rendering the generic "Session" fallback.
      |> assign(:program_names, StaffLiveHelpers.provider_program_names(provider_id))
      |> assign(:attendance, %{})
      |> assign(:active_nav, :roster)
      |> assign(:provider_id, provider_id)
      |> assign(:staff_member, staff_member)
      |> assign(:selected_date, selected_date)
      |> assign(:filter_program_id, nil)
      |> stream(:sessions, [])

    if connected?(socket) do
      Phoenix.PubSub.subscribe(KlassHero.PubSub, Participation.provider_topic(provider_id))
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    filter_program_id = params["program_id"]

    socket =
      socket
      |> assign(:filter_program_id, filter_program_id)
      |> load_sessions()

    {:noreply, socket}
  end

  @impl true
  def handle_event("change_date", %{"date" => date_string}, socket) do
    case Date.from_iso8601(date_string) do
      {:ok, new_date} ->
        socket =
          socket
          |> assign(:selected_date, new_date)
          |> load_sessions()

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Invalid date format"))}
    end
  end

  @impl true
  def handle_event("start_session", %{"session_id" => session_id}, socket) do
    case Participation.start_session(socket.assigns.current_scope, session_id) do
      {:ok, _session} ->
        {:noreply, put_flash(socket, :info, gettext("Session started successfully"))}

      {:error, reason} when reason in [:unauthorized, :program_closed] ->
        {:noreply, put_flash(socket, :error, ParticipationLiveHandlers.session_refusal_message(reason))}

      {:error, reason} ->
        Logger.error(
          "[StaffSessionsLive.start_session] Failed to start session",
          session_id: session_id,
          reason: inspect(reason),
          staff_member_id: socket.assigns.staff_member.id
        )

        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Failed to start session: %{reason}", reason: inspect(reason))
         )}
    end
  end

  @impl true
  def handle_event("complete_session", %{"session_id" => session_id}, socket) do
    case Participation.complete_session(socket.assigns.current_scope, session_id) do
      {:ok, _session} ->
        {:noreply, put_flash(socket, :info, gettext("Session completed successfully"))}

      {:error, reason} when reason in [:unauthorized, :program_closed] ->
        {:noreply, put_flash(socket, :error, ParticipationLiveHandlers.session_refusal_message(reason))}

      {:error, reason} ->
        Logger.error(
          "[StaffSessionsLive.complete_session] Failed to complete session",
          session_id: session_id,
          reason: inspect(reason),
          staff_member_id: socket.assigns.staff_member.id
        )

        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Failed to complete session: %{reason}", reason: inspect(reason))
         )}
    end
  end

  @impl true
  def handle_info({:session_changed, session_id}, socket) do
    {:noreply, update_session_in_stream(socket, session_id)}
  end

  # A generated batch spans many dates and is keyed on the program, so reload the
  # day being viewed rather than patching individual rows.
  @impl true
  def handle_info({:sessions_generated, _program_id}, socket) do
    {:noreply, load_sessions(socket)}
  end

  # Every attendance kind moves the session's checked-in count this view renders,
  # not only check-in.
  @impl true
  def handle_info({:attendance_changed, %{session_id: session_id}}, socket) do
    {:noreply, update_session_in_stream(socket, session_id)}
  end

  # The provider topic carries every participation message for this provider, not
  # only the ones this view renders.
  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  defp load_sessions(socket) do
    provider_id = socket.assigns.provider_id
    selected_date = socket.assigns.selected_date
    staff_member_id = socket.assigns.staff_member.id
    filter_program_id = socket.assigns.filter_program_id

    {:ok, sessions} = Participation.list_provider_sessions(provider_id, selected_date)

    # Batch, never per row: `list_session_staffing/1` costs four queries whatever
    # the day's session count, where a per-session call would N+1 the whole list.
    staffing = Provider.list_session_staffing(Enum.map(sessions, & &1.id))

    filtered =
      sessions
      |> Enum.filter(&SessionStaffing.staffed_by?(staffing[&1.id], staff_member_id))
      |> maybe_filter_by_program(filter_program_id)

    socket
    |> stream(:sessions, filtered, reset: true)
    |> assign(:attendance, Participation.session_attendance_counts(Enum.map(filtered, & &1.id)))
    |> assign(:sessions_error, nil)
  end

  # Narrows an already-authorized list, so it carries no access check of its own.
  # Reachable only by query param — no filter control exists in the template.
  defp maybe_filter_by_program(sessions, nil), do: sessions
  defp maybe_filter_by_program(sessions, ""), do: sessions

  defp maybe_filter_by_program(sessions, program_id) do
    Enum.filter(sessions, &(&1.program_id == program_id))
  end

  defp staffs_session?(socket, session_id) do
    session_id
    |> Provider.get_session_staffing()
    |> SessionStaffing.staffed_by?(socket.assigns.staff_member.id)
  end

  defp update_session_in_stream(socket, session_id) do
    case Participation.get_session_with_roster(session_id) do
      {:ok, %{session: session, roster: roster}} ->
        # Session events fan out across dates — a schedule edit cancels every
        # orphaned date, an enrolment seeds every upcoming roster — so check the
        # session's own date rather than trusting the event to concern this day.
        # Date first, and deliberately: it is an in-memory comparison while
        # `staffs_session?/2` costs a round trip, and this topic carries every
        # participation message for the provider, not only the ones this view
        # renders. `and` short-circuits, so an off-date message never queries.
        if session.session_date == socket.assigns.selected_date and
             staffs_session?(socket, session.id) do
          socket
          |> assign(
            :attendance,
            Map.put(socket.assigns.attendance, session.id, Participation.attendance_from_roster(roster))
          )
          |> stream_insert(:sessions, session)
        else
          socket
        end

      {:error, reason} ->
        Logger.error(
          "[StaffSessionsLive.update_session_in_stream] Failed to fetch session",
          session_id: session_id,
          reason: inspect(reason)
        )

        socket
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="staff-sessions" class="max-w-4xl mx-auto p-4 md:p-6">
      <div class="mb-6">
        <.page_header>
          <:title>{gettext("My Sessions")}</:title>
          <:subtitle>{gettext("View and manage your assigned sessions")}</:subtitle>
        </.page_header>
      </div>

      <div class="mb-6">
        <.date_selector
          id="date-select"
          name="date"
          value={@selected_date}
          label="Select Date:"
          phx_change="change_date"
        />
      </div>

      <.error_alert :if={assigns[:sessions_error]} errors={[@sessions_error]} />

      <div id="sessions" phx-update="stream" class="space-y-4">
        <div :for={{id, session} <- @streams.sessions} id={id}>
          <.participation_card
            session={session}
            role={:staff}
            program_name={@program_names[session.program_id]}
            attendance={@attendance[session.id]}
          >
            <:actions>
              <%= cond do %>
                <% session.status == :scheduled -> %>
                  <button
                    phx-click="start_session"
                    phx-value-session_id={session.id}
                    class={[
                      "px-4 py-2 bg-hero-blue-600 text-white font-medium hover:bg-hero-blue-700 focus:outline-none focus:ring-2 focus:ring-hero-blue-500 focus:ring-offset-2",
                      Theme.rounded(:lg),
                      Theme.transition(:normal)
                    ]}
                  >
                    {gettext("Start Session")}
                  </button>
                <% session.status == :in_progress -> %>
                  <.link
                    navigate={~p"/staff/participation/#{session.id}"}
                    class={[
                      "px-4 py-2 bg-hero-blue-600 text-white font-medium hover:bg-hero-blue-700 focus:outline-none focus:ring-2 focus:ring-hero-blue-500 focus:ring-offset-2 text-center",
                      Theme.rounded(:lg),
                      Theme.transition(:normal)
                    ]}
                  >
                    {gettext("Manage Participation")}
                  </.link>
                  <button
                    phx-click="complete_session"
                    phx-value-session_id={session.id}
                    class={[
                      "px-4 py-2 bg-gray-600 text-white font-medium hover:bg-gray-700 focus:outline-none focus:ring-2 focus:ring-gray-500 focus:ring-offset-2",
                      Theme.rounded(:lg),
                      Theme.transition(:normal)
                    ]}
                  >
                    {gettext("Complete Session")}
                  </button>
                <% session.status == :completed -> %>
                  <.link
                    navigate={~p"/staff/participation/#{session.id}"}
                    class={[
                      "px-4 py-2 bg-gray-100 text-gray-700 font-medium hover:bg-gray-200 focus:outline-none focus:ring-2 focus:ring-gray-500 focus:ring-offset-2 text-center",
                      Theme.rounded(:lg),
                      Theme.transition(:normal)
                    ]}
                  >
                    {gettext("View Participation")}
                  </.link>
                <% true -> %>
                  <span class="text-sm text-gray-500">{gettext("No actions available")}</span>
              <% end %>
            </:actions>
          </.participation_card>
        </div>

        <%!-- Empty state — needs id since it's a child of phx-update="stream" --%>
        <div id="sessions-empty" class="hidden only:block">
          <div class={[
            "p-8 text-center bg-white border border-gray-200",
            Theme.rounded(:lg),
            Theme.shadow(:md)
          ]}>
            <.icon name="hero-calendar" class="w-16 h-16 mx-auto mb-4 text-gray-400" />
            <h3 class={[Theme.typography(:card_title), "mb-2"]}>
              {gettext("No sessions scheduled")}
            </h3>
            <p class="text-gray-600">
              {gettext("You have no sessions scheduled for %{date}",
                date: Calendar.strftime(@selected_date, "%B %d, %Y")
              )}
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
