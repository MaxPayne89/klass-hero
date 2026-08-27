defmodule KlassHeroWeb.Provider.SessionsLive do
  use KlassHeroWeb, :live_view

  import KlassHeroWeb.ProviderComponents

  alias KlassHero.Participation
  alias KlassHero.ProgramCatalog
  alias KlassHero.Provider
  alias KlassHero.Provider.ReadModels.SessionStaffing
  alias KlassHeroWeb.Helpers.ParticipationLiveHandlers
  alias KlassHeroWeb.Helpers.SessionFormHandlers
  alias KlassHeroWeb.Helpers.TaskHelpers
  alias KlassHeroWeb.Presenters.ProgramStaffingPresenter
  alias KlassHeroWeb.Presenters.ProviderPresenter
  alias KlassHeroWeb.Theme

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    provider = socket.assigns.current_scope.provider
    provider_id = provider.id
    selected_date = Date.utc_today()

    # All queries are independent — fan out, await later
    programs_task =
      Task.Supervisor.async_nolink(KlassHero.TaskSupervisor, fn ->
        ProgramCatalog.list_programs_for_provider(provider_id)
      end)

    sessions_task =
      Task.Supervisor.async_nolink(KlassHero.TaskSupervisor, fn ->
        Participation.list_provider_sessions(provider_id, selected_date)
      end)

    docs_task =
      Task.Supervisor.async_nolink(KlassHero.TaskSupervisor, fn ->
        Provider.get_provider_verification_documents(provider_id)
      end)

    provider_programs =
      TaskHelpers.safe_await(programs_task, [], label: "SessionsLive.programs")

    docs = unwrap(TaskHelpers.safe_await(docs_task, {:ok, []}, label: "SessionsLive.docs"))

    business = build_business_view(provider, docs)

    socket =
      socket
      |> assign(:page_title, gettext("My Sessions"))
      |> assign(:active_nav, :roster)
      |> assign(:provider_id, provider_id)
      |> assign(:selected_date, selected_date)
      |> assign(:provider_programs, provider_programs)
      |> assign(:program_names, program_names(provider_programs))
      |> assign(:business, business)
      |> assign(:form, nil)
      |> assign(:session_staffing_modal, nil)
      |> stream(:sessions, [])

    if connected?(socket) do
      # Messages are pre-routed to the provider topic; no client-side filtering needed.
      Phoenix.PubSub.subscribe(KlassHero.PubSub, Participation.provider_topic(provider_id))
    end

    sessions_result =
      TaskHelpers.safe_await(sessions_task, {:ok, []}, label: "SessionsLive.sessions")

    socket = apply_sessions_result(socket, sessions_result)

    {:ok, socket}
  end

  # Mirrors the shape DashboardLive assigns so pv_dashboard_chrome renders identically across both LiveViews.
  defp build_business_view(provider, docs) do
    provider
    |> ProviderPresenter.to_business_view()
    |> Map.put(
      :verification_status,
      ProviderPresenter.verification_status_from_docs(provider.verified, docs)
    )
  end

  defp unwrap({:ok, value}), do: value
  defp unwrap(_), do: []

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, :form, nil)
  end

  defp apply_action(socket, :new, _params) do
    form_data = SessionFormHandlers.blank_form(socket.assigns.selected_date)

    assign(socket, :form, to_form(form_data, as: :session))
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

      {:error, reason} when reason in [:unauthorized, :not_found, :program_closed] ->
        {:noreply, put_flash(socket, :error, ParticipationLiveHandlers.session_refusal_message(reason))}

      {:error, reason} ->
        Logger.error(
          "[SessionsLive.start_session] Failed to start session",
          session_id: session_id,
          reason: inspect(reason),
          provider_id: socket.assigns.provider_id
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

      {:error, reason} when reason in [:unauthorized, :not_found, :program_closed] ->
        {:noreply, put_flash(socket, :error, ParticipationLiveHandlers.session_refusal_message(reason))}

      {:error, reason} ->
        Logger.error(
          "[SessionsLive.complete_session] Failed to complete session",
          session_id: session_id,
          reason: inspect(reason),
          provider_id: socket.assigns.provider_id
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
  def handle_event("validate_session", %{"session" => params}, socket) do
    params = SessionFormHandlers.prefill_from_program(params, socket.assigns.provider_programs)

    {:noreply, assign(socket, :form, to_form(params, as: :session))}
  end

  @impl true
  # Ownership is no longer checked here. `Participation.create_session/2` asks
  # `SessionAuthorization` itself (#1074), so a tampered program_id is refused for
  # every caller rather than for whichever surface remembered to look.
  def handle_event("save_session", %{"session" => params}, socket) do
    if params["program_id"] in [nil, ""] do
      {:noreply, put_flash(socket, :error, gettext("Program is required"))}
    else
      do_create_session(params, socket)
    end
  end

  @impl true
  def handle_event("close_new_session", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/provider/sessions")}
  end

  # --- Session staffing panel (#782) ---------------------------------------
  #
  # `session_id` arrives from the client, so every entry point goes through the
  # scoped read; foreign and unknown are indistinguishable, leaking no oracle.

  @impl true
  def handle_event("manage_session_staffing", %{"id" => session_id}, socket) do
    case build_session_staffing_modal(session_id, socket) do
      {:ok, modal} ->
        {:noreply, assign(socket, :session_staffing_modal, modal)}

      {:error, :not_found} ->
        {:noreply, session_staffing_not_found(socket, "open", session_id)}
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
    %{session_id: session_id} = socket.assigns.session_staffing_modal

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
    %{session_id: session_id} = socket.assigns.session_staffing_modal

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
    %{session_id: session_id} = socket.assigns.session_staffing_modal

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
    %{session_id: session_id} = socket.assigns.session_staffing_modal

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

  @impl true
  def handle_info({:session_changed, session_id}, socket) do
    {:noreply, update_session_in_stream(socket, session_id)}
  end

  # A generated batch is keyed on the program, not one session, and may span any
  # number of dates — so reload the day being viewed rather than patching rows.
  # The batch may also belong to a program created after mount, so refresh the
  # title map or its sessions would render under the generic fallback.
  @impl true
  def handle_info({:sessions_generated, _program_id}, socket) do
    programs = ProgramCatalog.list_programs_for_provider(socket.assigns.provider_id)

    socket =
      socket
      |> assign(:provider_programs, programs)
      |> assign(:program_names, program_names(programs))
      |> load_sessions()

    {:noreply, socket}
  end

  # Every attendance kind moves the session's checked-in count this view renders,
  # not only check-in.
  @impl true
  def handle_info({:attendance_changed, %{session_id: session_id}}, socket) do
    {:noreply, update_session_in_stream(socket, session_id)}
  end

  # The provider topic carries every participation message for this provider, not
  # only the ones this view renders — session notes already arrive here. Without
  # this, an unmatched message is a FunctionClauseError that takes the LiveView
  # down. Mirrors ParticipationLive and StaffParticipationLive.
  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  defp program_names(programs), do: Map.new(programs, &{&1.id, &1.title})

  # Two scoped facade reads joined by a presenter. `get_session_staffing_for_provider/2`
  # is the IDOR guard *and* the source of the override-vs-program fact the panel
  # renders — one call answers "may they see this?" and "where did this roster come
  # from?".
  defp build_session_staffing_modal(session_id, socket) do
    provider_id = socket.assigns.provider_id

    with {:ok, staffing} <- Provider.get_session_staffing_for_provider(provider_id, session_id) do
      lead_id = staffing.lead && staffing.lead.id

      members =
        session_id
        |> Provider.list_session_staff()
        |> ProgramStaffingPresenter.for_panel(lead_id)

      assignable =
        provider_id
        |> Provider.list_assignable_staff_for_session(session_id)
        |> staff_to_options()

      {:ok,
       %{
         session_id: session_id,
         session_label: session_label(session_id),
         program_title: Map.get(socket.assigns.program_names, staffing.program_id, gettext("Program")),
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
    %{session_id: session_id} = socket.assigns.session_staffing_modal

    case build_session_staffing_modal(session_id, socket) do
      {:ok, modal} -> assign(socket, :session_staffing_modal, modal)
      {:error, :not_found} -> assign(socket, :session_staffing_modal, nil)
    end
  end

  # Read rather than pulled off the stream: a stream is not enumerable state to
  # search, and the panel can be reopened after a reset has cleared the entry.
  defp session_label(session_id) do
    case Participation.get_session(session_id) do
      {:ok, session} -> Calendar.strftime(session.session_date, "%a, %d %b")
      {:error, :not_found} -> gettext("Session")
    end
  end

  defp staff_to_options(members) do
    Enum.map(members, fn m -> {Provider.staff_member_full_name(m), m.id} end)
  end

  defp session_staffing_not_found(socket, action, subject_id) do
    Logger.warning("[SessionsLive] Session staffing #{action} for unknown or foreign target",
      session_id: subject_id,
      provider_id: socket.assigns.provider_id
    )

    socket
    |> assign(:session_staffing_modal, nil)
    |> put_flash(:error, gettext("That session could not be found."))
  end

  defp load_sessions(socket) do
    result =
      Participation.list_provider_sessions(
        socket.assigns.provider_id,
        socket.assigns.selected_date
      )

    apply_sessions_result(socket, result)
  end

  defp apply_sessions_result(socket, {:ok, sessions}) do
    socket
    |> stream(:sessions, sessions, reset: true)
    |> assign(:attendance, Participation.session_attendance_counts(Enum.map(sessions, & &1.id)))
    |> assign(:sessions_error, nil)
  end

  defp apply_sessions_result(socket, {:error, reason}) do
    Logger.error(
      "[SessionsLive] Failed to load sessions for date #{socket.assigns.selected_date}",
      provider_id: socket.assigns.provider_id,
      reason: inspect(reason)
    )

    assign(socket, :sessions_error, reason)
  end

  defp do_create_session(params, socket) do
    case SessionFormHandlers.submit(socket.assigns.current_scope, params) do
      {:ok, _session} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Session created successfully"))
         |> push_patch(to: ~p"/provider/sessions")}

      {:error, reason} ->
        if !SessionFormHandlers.user_correctable?(reason) do
          Logger.error(
            "[SessionsLive.save_session] Failed to create session",
            reason: inspect(reason),
            provider_id: socket.assigns.provider_id
          )
        end

        {:noreply, put_flash(socket, :error, SessionFormHandlers.humanize_error(reason))}
    end
  end

  defp update_session_in_stream(socket, session_id) do
    case Participation.get_session_with_roster(session_id) do
      {:ok, %{session: session, roster: roster}} ->
        # Session events fan out across dates — a schedule edit cancels every
        # orphaned date at once, an enrolment seeds every upcoming roster — so
        # check the session's own date rather than trusting the event to concern
        # the day on screen.
        if session.session_date == socket.assigns.selected_date do
          # The roster came back with the session, so the recount is free.
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
          "[SessionsLive.update_session_in_stream] Failed to fetch session",
          session_id: session_id,
          reason: inspect(reason)
        )

        socket
    end
  end
end
