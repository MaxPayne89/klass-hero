defmodule KlassHeroWeb.DashboardLive do
  use KlassHeroWeb, :live_view

  import KlassHeroWeb.MessagingComponents, only: [contact_provider_button: 1]
  import KlassHeroWeb.ProgramComponents, only: [program_card: 1]

  alias KlassHero.Enrollment
  alias KlassHero.Family
  alias KlassHero.Family.Child
  alias KlassHero.Messaging
  alias KlassHero.Participation
  alias KlassHero.ProgramCatalog
  alias KlassHeroWeb.Helpers.Greeting
  alias KlassHeroWeb.Helpers.ProviderDisplay
  alias KlassHeroWeb.Presenters.ChildPresenter
  alias KlassHeroWeb.Presenters.ProgramPresenter
  alias KlassHeroWeb.Theme

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    socket =
      socket
      |> assign(
        page_title: Greeting.title(DateTime.utc_now(), user: user),
        page_subtitle: gettext("Your week with the kids"),
        active_nav: :home,
        user: user,
        loading?: true,
        waivers_outstanding: [],
        children_count: 0,
        kid_picker_items: [],
        active_program_count: 0,
        upcoming_count: 0,
        upcoming_sessions: [],
        recent_messages: [],
        unread_count: socket.assigns[:total_unread_count] || 0,
        family_programs_empty?: true
      )
      |> stream(:family_programs, [])
      |> maybe_start_load(user)

    {:ok, socket}
  end

  # Fetch on the connected mount only (runs once, not on the disconnected render).
  # Parent comes from the auth chain's already-resolved scope, not a fresh query.
  defp maybe_start_load(socket, user) do
    if connected?(socket) do
      parent = socket.assigns.current_scope.parent
      start_async(socket, :load_dashboard, fn -> load_dashboard_data(parent, user.id) end)
    else
      socket
    end
  end

  @impl true
  def handle_async(:load_dashboard, {:ok, data}, socket) do
    %{children: children, active_programs: active, expired_programs: expired} = data

    socket =
      socket
      |> assign(
        loading?: false,
        children_count: length(children),
        kid_picker_items: build_kid_picker_items(children, active),
        active_program_count: length(active),
        upcoming_count: length(data.upcoming_sessions),
        upcoming_sessions: data.upcoming_sessions,
        recent_messages: data.recent_messages,
        family_programs_empty?: active == [] and expired == [],
        waivers_outstanding: outstanding_waiver_items(active)
      )
      |> stream(:family_programs, build_family_program_items(active, expired), reset: true)

    {:noreply, socket}
  end

  def handle_async(:load_dashboard, {:exit, reason}, socket) do
    Logger.error("[DashboardLive] dashboard load failed", reason: inspect(reason))
    {:noreply, assign(socket, :loading?, false)}
  end

  defp load_dashboard_data(parent, user_id) do
    {children, active, expired} = load_family(parent)

    %{
      children: children,
      active_programs: active,
      expired_programs: expired,
      upcoming_sessions: load_upcoming_sessions(active, children),
      recent_messages: load_recent_messages(user_id)
    }
  end

  defp load_family(nil), do: {[], [], []}

  defp load_family(parent) do
    children = Family.get_children(parent.id)
    {active, expired} = load_family_programs(parent.id)
    {children, active, expired}
  end

  # Stable color rotation per child index keeps the palette consistent across mount cycles.
  defp build_kid_picker_items(children, active_programs) do
    counts =
      Enum.reduce(active_programs, %{}, fn {enrollment, _program}, acc ->
        Map.update(acc, enrollment.child_id, 1, &(&1 + 1))
      end)

    palette = ["#FFEAC9", "#33CFFF", "#FFFF36", "#FFD896"]

    children
    |> Enum.with_index()
    |> Enum.map(fn {child, idx} ->
      simple = ChildPresenter.to_simple_view(child)

      %{
        id: simple.id,
        name: simple.name,
        age: simple.age,
        programs: Map.get(counts, child.id, 0),
        color: Enum.at(palette, rem(idx, length(palette)))
      }
    end)
  end

  # Top 5 upcoming sessions across active programs, ascending by date.
  # One batched query; each session fans out to every {enrollment, program}
  # pair sharing its program (a program can hold more than one enrolled child).
  defp load_upcoming_sessions([], _children), do: []

  defp load_upcoming_sessions(active_programs, children) do
    children_by_id = Map.new(children, &{&1.id, &1})
    pairs_by_program = Enum.group_by(active_programs, fn {_enrollment, program} -> program.id end)

    pairs_by_program
    |> Map.keys()
    |> Participation.list_upcoming_sessions_for_programs(Date.utc_today())
    |> Enum.flat_map(fn session ->
      pairs_by_program
      |> Map.get(session.program_id, [])
      |> Enum.map(fn {enrollment, program} ->
        {enrollment, program, session, Map.get(children_by_id, enrollment.child_id)}
      end)
    end)
    |> Enum.sort_by(fn {_, _, session, _} -> session.session_date end, {:asc, Date})
    |> Enum.take(5)
    |> Enum.map(&format_upcoming_session/1)
  end

  defp format_upcoming_session({_enrollment, program, session, child}) do
    %{
      month: session.session_date |> Calendar.strftime("%b") |> String.upcase(),
      day: session.session_date.day,
      title: program.title,
      time: format_session_time(session),
      kid: child && Child.full_name(child),
      location: session.location,
      status: session.status
    }
  end

  defp format_session_time(%{start_time: %Time{} = start_t}), do: Calendar.strftime(start_t, "%H:%M")

  defp format_session_time(_), do: nil

  defp load_recent_messages(user_id) do
    {:ok, summaries, _has_more} = Messaging.list_conversations(user_id, limit: 4)
    palette = ["#FFEAC9", "#33CFFF", "#FFFF36"]

    for {summary, idx} <- Enum.with_index(summaries) do
      %{
        id: summary.conversation_id,
        from: gettext("Conversation"),
        preview: summary.latest_message_content || gettext("New conversation"),
        time: summary.latest_message_at && relative_time(summary.latest_message_at),
        color: Enum.at(palette, rem(idx, length(palette))),
        unread?: summary.unread_count > 0
      }
    end
  end

  defp relative_time(%DateTime{} = dt) do
    diff_seconds = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff_seconds < 60 -> "now"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m"
      diff_seconds < 86_400 -> "#{div(diff_seconds, 3600)}h"
      true -> "#{div(diff_seconds, 86_400)}d"
    end
  end

  defp relative_time(_), do: nil

  # An enrollment created by a provider's bulk invite has no signer at creation, so its
  # required waivers arrive outstanding. Only active programs are worth nagging about — a
  # finished program's unsigned waiver is a record to keep, not an action to take.
  defp outstanding_waiver_items([]), do: []

  defp outstanding_waiver_items(active_programs) do
    statuses =
      active_programs
      |> Enum.map(fn {enrollment, _program} -> enrollment.id end)
      |> Enrollment.waiver_status_for_enrollments()

    for {enrollment, program} <- active_programs,
        Map.get(statuses, enrollment.id) == :unsigned,
        do: %{enrollment_id: enrollment.id, program_title: program.title}
  end

  defp load_family_programs(parent_id) do
    enrollments = Enrollment.list_parent_enrollments(parent_id)

    program_ids = Enum.map(enrollments, & &1.program_id)
    programs_by_id = ProgramCatalog.get_programs_by_ids(program_ids) |> Map.new(&{&1.id, &1})

    enrollment_programs =
      Enum.flat_map(enrollments, fn enrollment ->
        case Map.fetch(programs_by_id, enrollment.program_id) do
          {:ok, program} ->
            [{enrollment, program}]

          :error ->
            Logger.warning("[DashboardLive] Enrollment references missing program",
              enrollment_id: enrollment.id,
              program_id: enrollment.program_id
            )

            []
        end
      end)

    Enrollment.classify_family_programs(enrollment_programs, Date.utc_today())
  end

  defp build_family_program_items(active, expired) do
    providers = ProviderDisplay.for_programs(Enum.map(active ++ expired, fn {_e, p} -> p end))

    active_items =
      Enum.map(active, fn {e, p} ->
        %{
          id: e.id,
          enrollment: e,
          program: p,
          provider: ProviderDisplay.fetch(providers, p),
          expired: false
        }
      end)

    expired_items =
      Enum.map(expired, fn {e, p} ->
        %{
          id: e.id,
          enrollment: e,
          program: p,
          provider: ProviderDisplay.fetch(providers, p),
          expired: true
        }
      end)

    active_items ++ expired_items
  end

  @impl true
  def handle_event("program_click", %{"program-id" => program_id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/programs/#{program_id}")}
  end

  def handle_event("select_kid", _params, socket) do
    # Kid-scoped filtering is a future enhancement; picker is purely visual for now.
    {:noreply, socket}
  end

  def handle_event("add_kid", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/family/settings/children/new")}
  end

  def handle_event("contact_provider", %{"program-id" => program_id, "provider-id" => provider_id}, socket) do
    case Messaging.start_program_conversation(
           socket.assigns.current_scope,
           provider_id,
           program_id
         ) do
      {:ok, conversation} ->
        {:noreply, push_navigate(socket, to: ~p"/messages/#{conversation.id}")}

      {:error, :not_entitled} ->
        {:noreply, put_flash(socket, :error, gettext("Upgrade your plan to send messages."))}

      {:error, reason} ->
        Logger.error("Failed to start program conversation from dashboard",
          reason: inspect(reason),
          provider_id: provider_id,
          program_id: program_id
        )

        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Could not start conversation. Please try again.")
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Enrollments created by a provider's bulk invite have no signer at creation, so
            their waivers arrive outstanding. This is the only place the parent learns that. --%>
      <section :if={@waivers_outstanding != []} id="waivers-outstanding">
        <div class={[
          "p-4 border",
          Theme.rounded(:xl),
          Theme.bg(:accent_light),
          Theme.border_color(:accent)
        ]}>
          <h2 class={["font-semibold mb-2", Theme.text_color(:heading)]}>
            {gettext("Waivers waiting for your signature")}
          </h2>
          <ul class="space-y-1 text-sm">
            <li :for={item <- @waivers_outstanding} id={"waivers-outstanding-#{item.enrollment_id}"}>
              <.link navigate={~p"/enrollments/#{item.enrollment_id}/waivers"} class="underline">
                {gettext("Sign the waivers for %{program}", program: item.program_title)}
              </.link>
            </li>
          </ul>
        </div>
      </section>

      <section :if={@kid_picker_items != []} id="kid-picker">
        <.pa_kid_picker
          kids={@kid_picker_items}
          active_id={nil}
          on_pick="select_kid"
          on_add="add_kid"
        />
      </section>

      <section id="dashboard-stats" class="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <.pa_stat_card
          title={gettext("Active programs")}
          value={Integer.to_string(@active_program_count)}
          icon="hero-academic-cap"
          tone={:primary}
        />
        <.pa_stat_card
          title={gettext("Upcoming this week")}
          value={Integer.to_string(@upcoming_count)}
          icon="hero-calendar"
          tone={:cool}
        />
        <.pa_stat_card
          title={gettext("Unread messages")}
          value={Integer.to_string(@unread_count)}
          icon="hero-chat-bubble-left-right"
          tone={:comic}
        />
      </section>

      <section class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <.pa_weekly_goal />
      </section>

      <section id="upcoming-sessions" class="bg-white rounded-2xl shadow-sm p-5">
        <div class="flex items-center justify-between mb-4">
          <h3 class="font-bold text-lg">{gettext("Upcoming sessions")}</h3>
          <.link
            navigate={~p"/participation"}
            class="text-sm font-bold text-[var(--brand-primary-dark)]"
          >
            {gettext("View all")} →
          </.link>
        </div>
        <div :if={@loading?} class="text-sm text-hero-grey-500">
          {gettext("Loading…")}
        </div>
        <div
          :if={@upcoming_sessions == [] and not @loading?}
          class="text-sm text-hero-grey-600"
        >
          {gettext("No upcoming sessions in the next few weeks.")}
        </div>
        <div class="space-y-1">
          <.pa_upcoming_item :for={s <- @upcoming_sessions} session={s} />
        </div>
      </section>

      <section id="messages-preview">
        <.pa_message_preview messages={@recent_messages} on_open_navigate="/messages" />
      </section>
      <section id="family-programs" class="mb-8">
        <div class="flex items-center gap-2 mb-4">
          <.icon name="hero-academic-cap-mini" class="w-6 h-6 text-hero-blue-600" />
          <h2 class="text-xl font-semibold text-hero-black-100">
            {gettext("Family Programs")}
          </h2>
        </div>

        <%= cond do %>
          <% @loading? -> %>
            <div
              id="family-programs-loading"
              class="text-center py-12 bg-white rounded-2xl shadow-sm text-hero-grey-500"
            >
              {gettext("Loading your programs…")}
            </div>
          <% @family_programs_empty? -> %>
            <div id="family-programs-empty" class="text-center py-12 bg-white rounded-2xl shadow-sm">
              <.icon name="hero-book-open" class="w-12 h-12 text-hero-grey-300 mx-auto mb-4" />
              <p class="text-hero-grey-500 mb-4">
                {gettext("No programs booked yet")}
              </p>
              <.link
                navigate={~p"/programs"}
                class={[
                  "inline-flex items-center px-6 py-3 text-white font-medium",
                  "bg-hero-blue-600 hover:bg-hero-blue-700",
                  Theme.rounded(:lg),
                  Theme.transition(:normal)
                ]}
              >
                {gettext("Book a Program")}
              </.link>
            </div>
          <% true -> %>
            <div
              id="family-programs-list"
              phx-update="stream"
              class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6"
            >
              <.program_card
                :for={{dom_id, item} <- @streams.family_programs}
                id={dom_id}
                program={ProgramPresenter.to_card_view(item.program, item.provider)}
                variant={:detailed}
                expired={item.expired}
                phx-click="program_click"
                phx-value-program-id={item.program.id}
              >
                <:actions :if={!item.expired}>
                  <.contact_provider_button
                    program_id={item.program.id}
                    provider_id={item.program.provider_id}
                    phx-click="contact_provider"
                  />
                </:actions>
              </.program_card>
            </div>
        <% end %>
      </section>
    </div>
    """
  end
end
