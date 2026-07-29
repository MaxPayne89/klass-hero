defmodule KlassHeroWeb.Provider.SessionsLive do
  use KlassHeroWeb, :live_view

  alias KlassHero.Participation
  alias KlassHero.ProgramCatalog
  alias KlassHero.Provider
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHeroWeb.Helpers.TaskHelpers
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

    provider_program_ids = MapSet.new(provider_programs, & &1.id)

    docs = unwrap(TaskHelpers.safe_await(docs_task, {:ok, []}, label: "SessionsLive.docs"))

    business = build_business_view(provider, docs)

    socket =
      socket
      |> assign(:page_title, gettext("My Sessions"))
      |> assign(:active_nav, :roster)
      |> assign(:provider_id, provider_id)
      |> assign(:selected_date, selected_date)
      |> assign(:provider_programs, provider_programs)
      |> assign(:provider_program_ids, provider_program_ids)
      |> assign(:business, business)
      |> assign(:form, nil)
      |> stream(:sessions, [])

    if connected?(socket) do
      # Events are pre-routed to the provider topic by NotifyLiveViews; no client-side filtering needed.
      Phoenix.PubSub.subscribe(
        KlassHero.PubSub,
        "participation:provider:#{provider_id}"
      )
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
    form_data = build_initial_form_data(socket.assigns.selected_date)

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
    case Participation.start_session(session_id) do
      {:ok, _session} ->
        {:noreply, put_flash(socket, :info, gettext("Session started successfully"))}

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
    case Participation.complete_session(session_id) do
      {:ok, _session} ->
        {:noreply, put_flash(socket, :info, gettext("Session completed successfully"))}

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
    params = maybe_prefill_from_program(params, socket.assigns.provider_programs)
    form = to_form(params, as: :session)

    {:noreply, assign(socket, :form, form)}
  end

  @impl true
  def handle_event("save_session", %{"session" => params}, socket) do
    program_id = params["program_id"]

    cond do
      program_id in [nil, ""] ->
        {:noreply, put_flash(socket, :error, gettext("Program is required"))}

      not MapSet.member?(socket.assigns.provider_program_ids, program_id) ->
        # Verify ownership server-side — the dropdown only shows their programs but form data can be tampered.
        {:noreply, put_flash(socket, :error, gettext("Unauthorized"))}

      true ->
        do_create_session(params, socket)
    end
  end

  @impl true
  def handle_info(
        {:domain_event, %DomainEvent{event_type: event_type, aggregate_id: session_id, payload: payload}},
        socket
      )
      when event_type in [:session_started, :session_completed, :session_created, :session_cancelled, :roster_seeded] do
    # session_created may be for a different date; only insert if it matches the current view.
    if event_type == :session_created and
         Map.get(payload, :session_date) != socket.assigns.selected_date do
      {:noreply, socket}
    else
      {:noreply, update_session_in_stream(socket, session_id)}
    end
  end

  # A generated batch is keyed on the program, not one session, and may span any
  # number of dates — so reload the day being viewed rather than patching rows.
  @impl true
  def handle_info({:domain_event, %DomainEvent{event_type: :sessions_generated}}, socket) do
    {:noreply, load_sessions(socket)}
  end

  @impl true
  def handle_info(
        {:domain_event, %DomainEvent{event_type: :child_checked_in, payload: %{session_id: session_id}}},
        socket
      ) do
    {:noreply, update_session_in_stream(socket, session_id)}
  end

  defp build_initial_form_data(selected_date) do
    %{
      "program_id" => "",
      "session_date" => Date.to_iso8601(selected_date),
      "start_time" => "",
      "end_time" => "",
      "location" => "",
      "notes" => "",
      "max_capacity" => ""
    }
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

  defp maybe_prefill_from_program(params, programs) do
    program_id = params["program_id"]

    case Enum.find(programs, &(&1.id == program_id)) do
      nil ->
        params

      program ->
        # Pre-fill time/location from program defaults; provider can still override any value.
        params
        |> maybe_set_default("start_time", format_time(program.meeting_start_time))
        |> maybe_set_default("end_time", format_time(program.meeting_end_time))
        |> maybe_set_default("location", program.location || "")
    end
  end

  # Don't overwrite values the provider has already typed.
  defp maybe_set_default(params, key, default) do
    if params[key] in [nil, ""] do
      Map.put(params, key, default)
    else
      params
    end
  end

  defp format_time(nil), do: ""
  defp format_time(%Time{} = time), do: Calendar.strftime(time, "%H:%M")

  defp do_create_session(params, socket) do
    case coerce_session_params(params) do
      {:ok, coerced} ->
        case Participation.create_session(coerced) do
          {:ok, _session} ->
            {:noreply,
             socket
             |> put_flash(:info, gettext("Session created successfully"))
             |> push_patch(to: ~p"/provider/sessions")}

          {:error, reason} when reason in [:invalid_time_range, :duplicate_session] ->
            # User-correctable domain error: show humanized message without "Failed" prefix.
            {:noreply, put_flash(socket, :error, humanize_error(reason))}

          {:error, reason} ->
            Logger.error(
              "[SessionsLive.save_session] Failed to create session",
              reason: inspect(reason),
              provider_id: socket.assigns.provider_id
            )

            {:noreply,
             put_flash(
               socket,
               :error,
               gettext("Failed to create session: %{reason}", reason: humanize_error(reason))
             )}
        end

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  defp coerce_session_params(params) do
    with {:ok, date} <- parse_date(params["session_date"]),
         {:ok, start_time} <- parse_time(params["start_time"]),
         {:ok, end_time} <- parse_time(params["end_time"]) do
      coerced = %{
        program_id: params["program_id"],
        session_date: date,
        start_time: start_time,
        end_time: end_time
      }

      coerced =
        if params["location"] in [nil, ""],
          do: coerced,
          else: Map.put(coerced, :location, params["location"])

      coerced =
        if params["notes"] in [nil, ""],
          do: coerced,
          else: Map.put(coerced, :notes, params["notes"])

      coerced =
        case Integer.parse(params["max_capacity"] || "") do
          {value, ""} when value > 0 -> Map.put(coerced, :max_capacity, value)
          _ -> coerced
        end

      {:ok, coerced}
    end
  end

  defp parse_date(nil), do: {:error, gettext("Date is required")}
  defp parse_date(""), do: {:error, gettext("Date is required")}

  defp parse_date(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, _date} = ok -> ok
      {:error, _} -> {:error, gettext("Invalid date format")}
    end
  end

  defp parse_time(nil), do: {:error, gettext("Time is required")}
  defp parse_time(""), do: {:error, gettext("Time is required")}

  defp parse_time(time_string) do
    # HTML time inputs produce "HH:MM"; Time.from_iso8601/1 requires "HH:MM:SS".
    normalized = if byte_size(time_string) == 5, do: time_string <> ":00", else: time_string

    case Time.from_iso8601(normalized) do
      {:ok, _time} = ok -> ok
      {:error, _} -> {:error, gettext("Invalid time format")}
    end
  end

  defp humanize_error(:invalid_time_range), do: gettext("End time must be after start time")
  defp humanize_error(:duplicate_session), do: gettext("A session already exists at this time")

  defp humanize_error(:missing_required_fields), do: gettext("Please fill in all required fields")

  defp humanize_error(reason), do: inspect(reason)

  defp update_session_in_stream(socket, session_id) do
    case Participation.get_session_with_roster(session_id) do
      {:ok, %{session: session}} ->
        stream_insert(socket, :sessions, session)

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
