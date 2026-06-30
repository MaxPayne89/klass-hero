defmodule KlassHeroWeb.Staff.StaffSessionsLive do
  use KlassHeroWeb, :live_view

  alias KlassHero.Participation
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHeroWeb.Helpers.StaffLiveHelpers
  alias KlassHeroWeb.Theme

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    staff_member = socket.assigns.current_scope.staff_member
    provider_id = staff_member.provider_id
    selected_date = Date.utc_today()

    {_programs, assigned_program_ids} = StaffLiveHelpers.load_assigned_programs(staff_member)

    socket =
      socket
      |> assign(:page_title, gettext("My Sessions"))
      |> assign(:active_nav, :roster)
      |> assign(:provider_id, provider_id)
      |> assign(:staff_member, staff_member)
      |> assign(:selected_date, selected_date)
      |> assign(:assigned_program_ids, assigned_program_ids)
      |> assign(:filter_program_id, nil)
      |> stream(:sessions, [])

    if connected?(socket) do
      Phoenix.PubSub.subscribe(
        KlassHero.PubSub,
        "participation:provider:#{provider_id}"
      )
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
    case authorize_session_action(session_id, socket) do
      :ok ->
        case Participation.start_session(session_id) do
          {:ok, _session} ->
            {:noreply, put_flash(socket, :info, gettext("Session started successfully"))}

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

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("Unauthorized"))}
    end
  end

  @impl true
  def handle_event("complete_session", %{"session_id" => session_id}, socket) do
    case authorize_session_action(session_id, socket) do
      :ok ->
        case Participation.complete_session(session_id) do
          {:ok, _session} ->
            {:noreply, put_flash(socket, :info, gettext("Session completed successfully"))}

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

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("Unauthorized"))}
    end
  end

  @impl true
  def handle_info(
        {:domain_event, %DomainEvent{event_type: event_type, aggregate_id: session_id, payload: payload}},
        socket
      )
      when event_type in [:session_started, :session_completed, :session_created, :roster_seeded] do
    if event_type == :session_created and
         Map.get(payload, :session_date) != socket.assigns.selected_date do
      {:noreply, socket}
    else
      {:noreply, update_session_in_stream(socket, session_id)}
    end
  end

  @impl true
  def handle_info(
        {:domain_event, %DomainEvent{event_type: :child_checked_in, payload: %{session_id: session_id}}},
        socket
      ) do
    {:noreply, update_session_in_stream(socket, session_id)}
  end

  defp load_sessions(socket) do
    provider_id = socket.assigns.provider_id
    selected_date = socket.assigns.selected_date
    assigned_program_ids = socket.assigns.assigned_program_ids
    filter_program_id = socket.assigns.filter_program_id

    {:ok, sessions} = Participation.list_provider_sessions(provider_id, selected_date)

    filtered =
      sessions
      |> Enum.filter(&MapSet.member?(assigned_program_ids, &1.program_id))
      |> maybe_filter_by_program(filter_program_id, assigned_program_ids)

    socket
    |> stream(:sessions, filtered, reset: true)
    |> assign(:sessions_error, nil)
  end

  defp maybe_filter_by_program(sessions, nil, _assigned_ids), do: sessions
  defp maybe_filter_by_program(sessions, "", _assigned_ids), do: sessions

  defp maybe_filter_by_program(sessions, program_id, assigned_ids) do
    if MapSet.member?(assigned_ids, program_id) do
      Enum.filter(sessions, &(&1.program_id == program_id))
    else
      sessions
    end
  end

  defp authorize_session_action(session_id, socket) do
    case Participation.get_session_with_roster(session_id) do
      {:ok, %{session: session}} ->
        if MapSet.member?(socket.assigns.assigned_program_ids, session.program_id) do
          :ok
        else
          {:error, :unauthorized}
        end

      {:error, _reason} ->
        {:error, :unauthorized}
    end
  end

  defp update_session_in_stream(socket, session_id) do
    case Participation.get_session_with_roster(session_id) do
      {:ok, %{session: session}} ->
        if MapSet.member?(socket.assigns.assigned_program_ids, session.program_id) do
          stream_insert(socket, :sessions, session)
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
          <.participation_card session={session} role={:staff}>
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
