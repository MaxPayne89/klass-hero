defmodule KlassHeroWeb.Provider.ProgramsLive do
  @moduledoc """
  Provider program management: the program inventory table, program create/edit
  form, the enrollment roster (with participant invites and CSV import), and the
  sessions modal.

  Split out of the former `DashboardLive` god-module (#904) — the heaviest tab.
  Owns the `programs` stream and every program/roster/invite/CSV event; renders
  inside the shared `pv_dashboard_shell`. Shared parsers and upload plumbing are
  imported from `Dashboard.Params`/`Dashboard.Uploads` so the moved helpers call
  them by their bare names, unchanged.

  The "New Program" header CTA (rendered on every tab) reaches this LiveView with
  `?new=1` from the other tabs; `mount/3` opens the form when that flag is present.
  """
  use KlassHeroWeb, :live_view

  import KlassHeroWeb.Provider.Dashboard.Params
  import KlassHeroWeb.Provider.Dashboard.Uploads
  import KlassHeroWeb.ProviderComponents

  alias KlassHero.Enrollment
  alias KlassHero.Messaging
  alias KlassHero.ProgramCatalog
  alias KlassHero.Provider
  alias KlassHeroWeb.Presenters.ProgramPresenter
  alias KlassHeroWeb.Presenters.StaffMemberPresenter
  alias KlassHeroWeb.Provider.Dashboard.Chrome

  require Logger

  @impl true
  def mount(params, _session, socket) do
    provider = socket.assigns.current_scope.provider

    domain_programs = ProgramCatalog.list_programs_for_provider(provider.id)
    enrollment_data = build_enrollment_data(domain_programs)
    programs = Enum.map(domain_programs, &ProgramPresenter.to_table_view(&1, enrollment_data))

    staff_members = fetch_staff_members(provider.id)
    staff_views = StaffMemberPresenter.to_admin_view_list(staff_members)

    staff_options =
      [%{value: "all", label: gettext("All Staff")}] ++
        Enum.map(staff_views, &%{value: &1.id, label: &1.full_name})

    socket =
      socket
      |> Chrome.assign()
      |> assign(page_title: gettext("My Programs"))
      |> assign(active_nav: :programs)
      |> stream(:programs, programs)
      |> assign(programs_count: length(programs))
      |> assign(staff_options: staff_options)
      |> assign(search_query: "", selected_staff: "all")
      |> assign(show_program_form: false, editing_program_id: nil)
      |> assign(
        show_roster: false,
        roster_program_name: nil,
        roster_program_id: nil,
        roster_entries: [],
        roster_tab: "enrolled",
        roster_invites: [],
        roster_enrolled_count: 0,
        roster_invite_count: 0,
        import_errors: nil,
        can_message?: false,
        invite_mode: "single",
        single_invite_form: blank_single_invite_form()
      )
      |> assign(sessions_modal: nil)
      |> assign(program_form: to_form(ProgramCatalog.new_program_changeset(), as: :program_schema))
      |> assign(enrollment_form: to_form(Enrollment.new_policy_changeset(), as: "enrollment_policy"))
      |> assign(
        participant_policy_form: to_form(Enrollment.new_participant_policy_changeset(), as: "participant_policy")
      )
      |> assign(instructor_options: build_instructor_options(staff_members))
      |> assign(categories: ProgramCatalog.program_categories())
      |> allow_upload(:program_cover,
        accept: ~w(.jpg .jpeg .png .webp),
        max_entries: 1,
        max_file_size: 2_000_000
      )
      |> allow_upload(:csv_file,
        accept: ~w(.csv),
        max_entries: 1,
        max_file_size: 2_000_000
      )
      |> maybe_open_new_program_form(params)

    {:ok, socket}
  end

  # Arriving from another tab's "New Program" CTA (`?new=1`): open the form on mount.
  defp maybe_open_new_program_form(socket, %{"new" => "1"}) do
    assign(socket, show_program_form: true)
  end

  defp maybe_open_new_program_form(socket, _params), do: socket

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref, "upload" => upload_name}, socket) do
    {:noreply, cancel_upload(socket, String.to_existing_atom(upload_name), ref)}
  end

  @impl true
  def handle_event("add_program", _params, socket) do
    # The header CTA on this tab opens the form in place. From the other tabs it
    # arrives as a navigate to `?new=1`, handled in mount/3.
    {:noreply,
     socket
     |> assign(show_program_form: true, editing_program_id: nil)
     |> assign(program_form: to_form(ProgramCatalog.new_program_changeset(), as: :program_schema))
     |> assign(enrollment_form: to_form(Enrollment.new_policy_changeset(), as: "enrollment_policy"))
     |> assign(
       participant_policy_form: to_form(Enrollment.new_participant_policy_changeset(), as: "participant_policy")
     )
     |> assign(instructor_options: build_instructor_options(socket.assigns.current_scope.provider.id))}
  end

  @impl true
  def handle_event("edit_program", %{"id" => program_id}, socket) do
    case ProgramCatalog.get_program_by_id(program_id) do
      {:ok, program} ->
        changeset = ProgramCatalog.new_program_changeset(program_to_form_params(program))

        {:noreply,
         socket
         |> assign(
           show_program_form: true,
           editing_program_id: program_id,
           program_form: to_form(changeset, as: :program_schema),
           enrollment_form: load_enrollment_policy_form(program_id),
           participant_policy_form: load_participant_policy_form(program_id),
           instructor_options: build_instructor_options(socket.assigns.current_scope.provider.id)
         )}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, gettext("Program not found."))}
    end
  end

  @impl true
  def handle_event("view_roster", %{"id" => program_id}, socket) do
    provider_id = socket.assigns.current_scope.provider.id

    # Verify ownership before loading — program_id is untrusted client input (IDOR guard).
    with {:ok, program} <- ProgramCatalog.get_program_by_id(program_id),
         true <- program.provider_id == provider_id do
      roster = Enrollment.list_program_enrollments(program_id)
      invite_count = Enrollment.count_program_invites(program_id)

      {:noreply,
       assign(socket,
         show_roster: true,
         roster_program_name: program.title,
         roster_program_id: program_id,
         roster_entries: roster,
         roster_tab: "enrolled",
         roster_invites: [],
         roster_enrolled_count: length(roster),
         roster_invite_count: invite_count,
         import_errors: nil,
         can_message?: Messaging.can_initiate_messaging?(socket.assigns.current_scope),
         invite_mode: "single",
         single_invite_form: blank_single_invite_form()
       )}
    else
      false ->
        Logger.warning("[ProgramsLive] Unauthorized roster access attempt",
          program_id: program_id,
          provider_id: provider_id
        )

        {:noreply, put_flash(socket, :error, gettext("Program not found."))}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, gettext("Program not found."))}
    end
  end

  @impl true
  def handle_event("close_roster", _params, socket) do
    {:noreply,
     assign(socket,
       show_roster: false,
       roster_entries: [],
       roster_tab: "enrolled",
       roster_invites: [],
       roster_program_id: nil,
       roster_invite_count: 0,
       roster_enrolled_count: 0,
       import_errors: nil,
       can_message?: false,
       invite_mode: "single",
       single_invite_form: blank_single_invite_form()
     )}
  end

  # list_program_sessions/2 is scoped to provider_id, so a spoofed program_id leaks nothing.
  # Title is derived from the projection result, not client params.
  @impl true
  def handle_event("view_sessions", %{"program-id" => program_id}, socket) do
    provider_id = socket.assigns.current_scope.provider.id
    sessions = Provider.list_program_sessions(provider_id, program_id)

    program_title =
      case List.first(sessions) do
        %{program_title: title} -> title
        nil -> gettext("Program")
      end

    {:noreply,
     assign(socket, :sessions_modal, %{
       program_id: program_id,
       program_title: program_title,
       sessions: sessions
     })}
  end

  @impl true
  def handle_event("close_sessions", _params, socket) do
    {:noreply, assign(socket, :sessions_modal, nil)}
  end

  @impl true
  def handle_event("send_message_to_parent", %{"parent-user-id" => parent_user_id}, socket) do
    scope = socket.assigns.current_scope
    provider_id = scope.provider.id
    roster_entries = socket.assigns.roster_entries

    # parent_user_id is untrusted; validate against server-side roster to block unauthorized messaging.
    valid_confirmed? =
      Enum.any?(roster_entries, fn entry ->
        entry.parent_user_id == parent_user_id and entry.status == :confirmed
      end)

    if valid_confirmed? do
      case Messaging.create_direct_conversation(scope, provider_id, parent_user_id) do
        {:ok, conversation} ->
          {:noreply, push_navigate(socket, to: ~p"/provider/messages/#{conversation.id}")}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Could not start conversation. Please try again."))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Cannot message this parent."))}
    end
  end

  @impl true
  def handle_event("switch_roster_tab", %{"tab" => "invites"}, socket) do
    case refresh_invites(socket, socket.assigns.roster_program_id) do
      {:ok, socket} -> {:noreply, assign(socket, roster_tab: "invites")}
      {:error, :no_program} -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("switch_roster_tab", %{"tab" => "enrolled"}, socket) do
    {:noreply, assign(socket, roster_tab: "enrolled")}
  end

  @impl true
  def handle_event("resend_invite", %{"id" => invite_id}, socket) do
    provider_id = socket.assigns.current_scope.provider.id

    case Enrollment.resend_invite(invite_id, provider_id) do
      {:ok, _} ->
        socket = refresh_invites_silent(socket, socket.assigns.roster_program_id)

        {:noreply, put_flash(socket, :info, gettext("Invite resent successfully."))}

      {:error, :not_resendable} ->
        {:noreply, put_flash(socket, :error, gettext("This invite cannot be resent."))}

      {:error, reason} ->
        Logger.warning("[ProgramsLive] Resend invite failed unexpectedly",
          invite_id: invite_id,
          reason: inspect(reason)
        )

        {:noreply, put_flash(socket, :error, gettext("Failed to resend invite."))}
    end
  end

  @impl true
  def handle_event("delete_invite", %{"id" => invite_id}, socket) do
    provider_id = socket.assigns.current_scope.provider.id

    case Enrollment.delete_invite(invite_id, provider_id) do
      :ok ->
        socket = refresh_invites_silent(socket, socket.assigns.roster_program_id)

        {:noreply, put_flash(socket, :info, gettext("Invite removed."))}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, gettext("Invite not found."))}

      {:error, :delete_failed} ->
        {:noreply, put_flash(socket, :error, gettext("Could not remove invite."))}
    end
  end

  @impl true
  def handle_event("validate_csv_upload", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_csv_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :csv_file, ref)}
  end

  @impl true
  def handle_event("import_csv", _params, socket) do
    provider_id = socket.assigns.current_scope.provider.id
    program_id = socket.assigns.roster_program_id

    # Wrap File.read/1 result so consume_uploaded_entries doesn't unwrap the inner {:ok, binary}.
    # sobelow_skip ["Traversal.FileModule"]
    case safe_consume_uploaded_entries(socket, :csv_file, fn %{path: path}, _entry ->
           {:ok, File.read(path)}
         end) do
      {:error, :upload_channel_died} ->
        {:noreply, put_flash(socket, :error, gettext("Upload connection lost. Please try again."))}

      {:ok, []} ->
        {:noreply, put_flash(socket, :error, gettext("No file selected."))}

      {:ok, [{:error, reason}]} ->
        Logger.warning("[ProgramsLive] CSV file read failed: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, gettext("Could not read the uploaded file."))}

      {:ok, [{:ok, csv_binary}]} ->
        case Enrollment.import_enrollment_csv(provider_id, csv_binary) do
          {:ok, %{created: count, failed: []}} ->
            socket = refresh_invites_silent(socket, program_id)

            {:noreply,
             socket
             |> put_flash(
               :info,
               ngettext("Imported %{count} family.", "Imported %{count} families.", count)
             )
             |> assign(import_errors: nil)}

          {:ok, %{created: 0, failed: failed}} ->
            {:noreply,
             socket
             |> put_flash(
               :error,
               ngettext(
                 "No rows imported. %{count} row could not be processed.",
                 "No rows imported. %{count} rows could not be processed.",
                 length(failed)
               )
             )
             |> assign(import_errors: failed)}

          {:ok, %{created: count, failed: failed}} ->
            socket = refresh_invites_silent(socket, program_id)

            # Two separate ngettext calls keep plural rules independent — translators can pluralise each half correctly.
            imported_msg =
              ngettext("Imported %{count} family.", "Imported %{count} families.", count)

            failed_msg =
              ngettext(
                "%{count} row could not be processed.",
                "%{count} rows could not be processed.",
                length(failed)
              )

            {:noreply,
             socket
             |> put_flash(:info, imported_msg <> " " <> failed_msg)
             |> assign(import_errors: failed)}

          {:error, error_report} ->
            {:noreply, assign(socket, import_errors: error_report)}
        end
    end
  end

  @impl true
  def handle_event("switch_invite_mode", %{"mode" => mode}, socket) when mode in ~w(single csv) do
    {:noreply, assign(socket, invite_mode: mode)}
  end

  # Catch-all: ignore unknown modes rather than crash the LV. The pills
  # above only emit "single" / "csv", but a buggy Hook or crafted channel
  # message could send anything; we want the socket to stay alive.
  @impl true
  def handle_event("switch_invite_mode", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("validate_single_invite", %{"single_invite" => params}, socket) do
    changeset = params |> Enrollment.change_single_invite() |> Map.put(:action, :validate)
    {:noreply, assign(socket, single_invite_form: to_form(changeset, as: "single_invite"))}
  end

  @impl true
  def handle_event("submit_single_invite", %{"single_invite" => params}, socket) do
    provider_id = socket.assigns.current_scope.provider.id

    case Enrollment.invite_single_participant(provider_id, params) do
      {:ok, _} ->
        socket = refresh_invites_silent(socket, socket.assigns.roster_program_id)

        {:noreply,
         socket
         |> put_flash(:info, gettext("Invite sent."))
         |> assign(single_invite_form: blank_single_invite_form())}

      {:error, :no_programs} ->
        {:noreply, put_flash(socket, :error, gettext("Create a program before inviting participants."))}

      {:error, :duplicate} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("An invite for this child and program already exists.")
         )}

      {:error, %{validation_errors: field_errors}} ->
        changeset =
          params
          |> Enrollment.change_single_invite()
          |> Enrollment.apply_single_invite_domain_errors(field_errors)

        {:noreply, assign(socket, single_invite_form: to_form(changeset, as: "single_invite"))}
    end
  end

  @impl true
  def handle_event("close_program_form", _params, socket) do
    {:noreply,
     assign(socket,
       show_program_form: false,
       editing_program_id: nil,
       enrollment_form: to_form(Enrollment.new_policy_changeset(), as: "enrollment_policy"),
       participant_policy_form: to_form(Enrollment.new_participant_policy_changeset(), as: "participant_policy")
     )}
  end

  @impl true
  def handle_event("validate_program", params, socket) do
    program_params = params["program_schema"] || %{}

    changeset =
      ProgramCatalog.new_program_changeset(program_params)
      |> Map.put(:action, :validate)

    enrollment_params = params["enrollment_policy"] || %{}

    enrollment_changeset =
      Enrollment.new_policy_changeset(enrollment_params)
      |> Map.put(:action, :validate)

    participant_policy_params = params["participant_policy"] || %{}

    participant_policy_changeset =
      Enrollment.new_participant_policy_changeset(participant_policy_params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(program_form: to_form(changeset, as: :program_schema))
     |> assign(enrollment_form: to_form(enrollment_changeset, as: "enrollment_policy"))
     |> assign(participant_policy_form: to_form(participant_policy_changeset, as: "participant_policy"))}
  end

  @impl true
  def handle_event("save_program", %{"program_schema" => params} = all_params, socket) do
    provider = socket.assigns.current_scope.provider

    cover_result = upload_program_cover(socket, provider.id)

    attrs =
      %{
        provider_id: provider.id,
        title: params["title"],
        description: params["description"],
        category: params["category"],
        price: parse_decimal(params["price"]),
        location: presence(params["location"]),
        meeting_days: parse_meeting_days(params["meeting_days"]),
        meeting_start_time: parse_time(params["meeting_start_time"]),
        meeting_end_time: parse_time(params["meeting_end_time"]),
        start_date: parse_date(params["start_date"]),
        end_date: parse_date(params["end_date"]),
        registration_start_date: parse_date(params["registration_start_date"]),
        registration_end_date: parse_date(params["registration_end_date"])
      }
      |> maybe_add_cover_image(cover_result)

    case socket.assigns.editing_program_id do
      nil ->
        create_new_program(socket, attrs, all_params, cover_result)

      program_id ->
        update_existing_program(socket, program_id, attrs, all_params, cover_result)
    end
  end

  @impl true
  def handle_event("search_programs", %{"search" => query}, socket) do
    {:noreply,
     socket
     |> assign(search_query: query)
     |> reset_programs_stream()}
  end

  @impl true
  def handle_event("filter_by_staff", %{"staff_filter" => staff_id}, socket) do
    {:noreply,
     socket
     |> assign(selected_staff: staff_id)
     |> reset_programs_stream()}
  end

  defp create_new_program(socket, attrs, all_params, cover_result) do
    program_params = all_params["program_schema"] || %{}
    enrollment_params = all_params["enrollment_policy"] || %{}
    participant_policy_params = all_params["participant_policy"] || %{}

    with {:ok, attrs} <- maybe_add_instructor(attrs, program_params["instructor_id"], socket),
         {:ok, program} <- ProgramCatalog.create_program(attrs) do
      policy_result = maybe_set_enrollment_policy(program.id, enrollment_params)
      set_participant_policy_on_create(program.id, participant_policy_params)
      capacity = resolve_capacity(policy_result, enrollment_params)

      new_enrollment_data = %{
        program.id => %{enrolled: 0, capacity: capacity}
      }

      view = ProgramPresenter.to_table_view(program, new_enrollment_data)

      {:noreply,
       socket
       |> flash_for_policy_result(policy_result)
       |> maybe_flash_cover_warning(cover_result)
       |> stream_insert(:programs, view)
       |> assign(
         show_program_form: false,
         editing_program_id: nil,
         programs_count: socket.assigns.programs_count + 1,
         enrollment_form: to_form(Enrollment.new_policy_changeset(), as: "enrollment_policy"),
         participant_policy_form: to_form(Enrollment.new_participant_policy_changeset(), as: "participant_policy")
       )}
    else
      {:error, :instructor_not_found} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Selected instructor could not be found. Please try again.")
         )}

      {:error, errors} when is_list(errors) ->
        {:noreply, put_flash(socket, :error, Enum.join(errors, ", "))}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(program_form: to_form(Map.put(changeset, :action, :validate), as: :program_schema))
         |> put_flash(:error, gettext("Please fix the errors below."))}
    end
  end

  defp update_existing_program(socket, program_id, attrs, all_params, cover_result) do
    program_params = all_params["program_schema"] || %{}
    enrollment_params = all_params["enrollment_policy"] || %{}
    participant_policy_params = all_params["participant_policy"] || %{}

    with {:ok, attrs} <- maybe_add_instructor(attrs, program_params["instructor_id"], socket),
         {:ok, updated} <- ProgramCatalog.update_program(program_id, attrs) do
      policy_result = maybe_set_enrollment_policy(program_id, enrollment_params)
      set_participant_policy_on_update(program_id, participant_policy_params)

      capacity = resolve_capacity(policy_result, enrollment_params)
      active_counts = Enrollment.count_active_enrollments_batch([program_id])
      enrolled = Map.get(active_counts, program_id, 0)
      enrollment_data = %{program_id => %{enrolled: enrolled, capacity: capacity}}
      view = ProgramPresenter.to_table_view(updated, enrollment_data)

      {:noreply,
       socket
       |> put_flash(:info, gettext("Program updated successfully."))
       |> maybe_flash_cover_warning(cover_result)
       |> stream_insert(:programs, view)
       |> assign(
         show_program_form: false,
         editing_program_id: nil,
         enrollment_form: to_form(Enrollment.new_policy_changeset(), as: "enrollment_policy"),
         participant_policy_form: to_form(Enrollment.new_participant_policy_changeset(), as: "participant_policy")
       )}
    else
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, gettext("Program not found."))}

      {:error, :stale_data} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("This program was modified by someone else. Please close and try again.")
         )}

      {:error, :instructor_not_found} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Selected instructor could not be found. Please try again.")
         )}

      {:error, errors} when is_list(errors) ->
        {:noreply, put_flash(socket, :error, Enum.join(errors, ", "))}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(program_form: to_form(Map.put(changeset, :action, :validate), as: :program_schema))
         |> put_flash(:error, gettext("Please fix the errors below."))}
    end
  end

  defp refresh_invites(_socket, nil), do: {:error, :no_program}

  defp refresh_invites(socket, program_id) when is_binary(program_id) do
    {:ok, invites} = Enrollment.list_program_invites(program_id)
    invite_count = Enrollment.count_program_invites(program_id)
    {:ok, assign(socket, roster_invites: invites, roster_invite_count: invite_count)}
  end

  defp refresh_invites_silent(socket, program_id) do
    case refresh_invites(socket, program_id) do
      {:ok, socket} -> socket
      {:error, :no_program} -> socket
    end
  end

  defp blank_single_invite_form do
    to_form(Enrollment.change_single_invite(), as: "single_invite")
  end

  # Aggregate pending invites across all provider programs and shape them
  # for `pv_request_card` (parent name, program, child, when, color).
  defp fetch_staff_members(provider_id) do
    {:ok, members} = Provider.list_staff_members(provider_id)
    members
  end

  defp reset_programs_stream(socket) do
    provider_id = socket.assigns.current_scope.provider.id
    domain_programs = ProgramCatalog.list_programs_for_provider(provider_id)
    enrollment_data = build_enrollment_data(domain_programs)

    programs =
      domain_programs
      |> Enum.map(&ProgramPresenter.to_table_view(&1, enrollment_data))
      |> filter_by_search(socket.assigns.search_query)
      |> filter_by_staff(socket.assigns.selected_staff)

    socket
    |> stream(:programs, programs, reset: true)
    |> assign(programs_count: length(programs))
  end

  defp build_enrollment_data(domain_programs) do
    program_ids = Enum.map(domain_programs, & &1.id)
    Enrollment.get_enrollment_summary_batch(program_ids)
  end

  defp filter_by_search(programs, ""), do: programs

  defp filter_by_search(programs, query) do
    query_lower = String.downcase(query)

    Enum.filter(programs, fn program ->
      String.contains?(String.downcase(program.name), query_lower)
    end)
  end

  defp filter_by_staff(programs, "all"), do: programs

  defp filter_by_staff(programs, staff_id) do
    Enum.filter(programs, fn program ->
      program.assigned_staff && to_string(program.assigned_staff.id) == staff_id
    end)
  end

  defp upload_program_cover(socket, provider_id) do
    consume_single_upload(socket, :program_cover, "program_covers", provider_id)
  end

  defp maybe_add_cover_image(attrs, {:ok, url}), do: Map.put(attrs, :cover_image_url, url)
  defp maybe_add_cover_image(attrs, :no_upload), do: attrs

  defp maybe_add_cover_image(attrs, :upload_error), do: attrs

  defp maybe_flash_cover_warning(socket, :upload_error) do
    put_flash(
      socket,
      :warning,
      gettext("Program saved, but the cover image upload failed. You can re-upload it by editing the program.")
    )
  end

  defp maybe_flash_cover_warning(socket, _cover_result), do: socket

  defp maybe_add_instructor(attrs, nil, _socket), do: {:ok, attrs}
  defp maybe_add_instructor(attrs, "", _socket), do: {:ok, attrs}

  defp maybe_add_instructor(attrs, instructor_id, socket) do
    case Provider.get_staff_member(instructor_id) do
      {:ok, staff} ->
        {:ok,
         Map.put(attrs, :instructor, %{
           id: staff.id,
           name: Provider.staff_member_full_name(staff),
           headshot_url: staff.headshot_url
         })}

      {:error, _reason} ->
        Logger.warning("Instructor not found during program creation",
          instructor_id: instructor_id,
          provider_id: socket.assigns.current_scope.provider.id
        )

        {:error, :instructor_not_found}
    end
  end

  # Builds instructor options from an already-fetched list of StaffMember domain structs.
  # Avoids a redundant DB query when the full list is already in scope (e.g. mount).
  defp build_instructor_options(staff_members) when is_list(staff_members) do
    for m <- staff_members, m.active, do: {Provider.staff_member_full_name(m), m.id}
  end

  defp build_instructor_options(provider_id) do
    {:ok, members} = Provider.list_active_staff_members(provider_id)
    staff_to_options(members)
  end

  defp staff_to_options(members) do
    Enum.map(members, fn m -> {Provider.staff_member_full_name(m), m.id} end)
  end

  defp maybe_set_enrollment_policy(program_id, params) do
    min = parse_integer(params["min_enrollment"])
    max = parse_integer(params["max_enrollment"])

    if is_nil(min) and is_nil(max) do
      :ok
    else
      case Enrollment.set_enrollment_policy(%{
             program_id: program_id,
             min_enrollment: min,
             max_enrollment: max
           }) do
        {:ok, _policy} ->
          :ok

        # Program already created — don't roll back, propagate error to show a warning flash.
        {:error, reason} ->
          Logger.warning("[Provider.ProgramsLive] Failed to save enrollment policy",
            program_id: program_id,
            reason: inspect(reason)
          )

          {:error, :enrollment_policy_failed}
      end
    end
  end

  # Skip upsert on create when all restriction fields are empty — avoid storing an all-nil row.
  defp set_participant_policy_on_create(program_id, params) do
    parsed = parse_participant_policy_params(params)

    case build_create_policy_attrs(program_id, parsed) do
      nil -> :ok
      attrs -> save_participant_policy(attrs, program_id)
    end
  end

  # Trigger: existing program edit — must allow clearing previously stored restrictions
  # Why: short-circuiting on all-empty would leave stale DB values in place (issue #795)
  # Outcome: always upsert, carrying explicit nils so on_conflict replaces stored values
  defp set_participant_policy_on_update(program_id, params) do
    parsed = parse_participant_policy_params(params)

    program_id
    |> build_update_policy_attrs(parsed)
    |> save_participant_policy(program_id)
  end

  defp parse_participant_policy_params(params) do
    %{
      eligibility_at: presence(params["eligibility_at"]),
      min_age_months: parse_integer(params["min_age_months"]),
      max_age_months: parse_integer(params["max_age_months"]),
      min_grade: parse_integer(params["min_grade"]),
      max_grade: parse_integer(params["max_grade"]),
      # Hidden input for checkbox group sends [""] when none checked — reject to get a clean list.
      allowed_genders: Enum.reject(params["allowed_genders"] || [], &(&1 == ""))
    }
  end

  defp build_create_policy_attrs(program_id, parsed) do
    if any_restriction?(parsed) do
      parsed
      |> Map.put(:program_id, program_id)
      |> drop_nil_eligibility_at()
    end
  end

  defp build_update_policy_attrs(program_id, parsed) do
    parsed
    |> Map.put(:program_id, program_id)
    |> drop_nil_eligibility_at()
  end

  defp any_restriction?(%{
         min_age_months: nil,
         max_age_months: nil,
         min_grade: nil,
         max_grade: nil,
         allowed_genders: []
       }), do: false

  defp any_restriction?(_parsed), do: true

  # nil is unreachable from the form (radio always submits a value) but would violate NOT NULL.
  # Drop the key so INSERT falls back to the schema default ("registration").
  defp save_participant_policy(attrs, program_id) do
    case Enrollment.set_participant_policy(attrs) do
      {:ok, _policy} ->
        :ok

      {:error, reason} ->
        Logger.warning("[Provider.ProgramsLive] Failed to save participant policy",
          program_id: program_id,
          reason: inspect(reason)
        )

        {:error, :participant_policy_failed}
    end
  end

  defp resolve_capacity(:ok, enrollment_params), do: parse_integer(enrollment_params["max_enrollment"])

  defp resolve_capacity({:error, _}, _enrollment_params), do: nil

  defp flash_for_policy_result(socket, :ok) do
    socket
    |> clear_flash(:error)
    |> put_flash(:info, gettext("Program created successfully."))
  end

  defp flash_for_policy_result(socket, {:error, :enrollment_policy_failed}) do
    socket
    |> put_flash(
      :error,
      gettext("Program created, but enrollment capacity could not be saved. Edit the program to retry.")
    )
  end

  defp program_to_form_params(program) do
    %{
      "title" => program.title,
      "description" => program.description,
      "category" => program.category,
      "price" => nil_safe(program.price, &Decimal.to_string/1),
      "location" => program.location,
      "instructor_id" => nil_safe(program.instructor, & &1.id),
      "meeting_days" => program.meeting_days || [],
      "meeting_start_time" => nil_safe(program.meeting_start_time, &Time.to_iso8601/1),
      "meeting_end_time" => nil_safe(program.meeting_end_time, &Time.to_iso8601/1),
      "start_date" => nil_safe(program.start_date, &Date.to_iso8601/1),
      "end_date" => nil_safe(program.end_date, &Date.to_iso8601/1),
      "registration_start_date" => nil_safe(program.registration_period.start_date, &Date.to_iso8601/1),
      "registration_end_date" => nil_safe(program.registration_period.end_date, &Date.to_iso8601/1)
    }
  end

  defp load_enrollment_policy_form(program_id) do
    case Enrollment.get_enrollment_policy(program_id) do
      {:ok, policy} ->
        to_form(
          Enrollment.new_policy_changeset(%{
            "min_enrollment" => policy.min_enrollment && to_string(policy.min_enrollment),
            "max_enrollment" => policy.max_enrollment && to_string(policy.max_enrollment)
          }),
          as: "enrollment_policy"
        )

      {:error, :not_found} ->
        to_form(Enrollment.new_policy_changeset(), as: "enrollment_policy")
    end
  end

  defp load_participant_policy_form(program_id) do
    case Enrollment.get_participant_policy(program_id) do
      {:ok, policy} ->
        to_form(
          Enrollment.new_participant_policy_changeset(%{
            "min_age_months" => policy.min_age_months && to_string(policy.min_age_months),
            "max_age_months" => policy.max_age_months && to_string(policy.max_age_months),
            "min_grade" => policy.min_grade && to_string(policy.min_grade),
            "max_grade" => policy.max_grade && to_string(policy.max_grade),
            "allowed_genders" => policy.allowed_genders || [],
            "eligibility_at" => policy.eligibility_at
          }),
          as: "participant_policy"
        )

      {:error, :not_found} ->
        to_form(Enrollment.new_participant_policy_changeset(), as: "participant_policy")
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.pv_dashboard_shell
      business={@business}
      current_tab={:programs}
      profile_draft?={@profile_draft?}
      dual_role?={@dual_role?}
    >
      <div class="space-y-6">
        <%= if @show_program_form do %>
          <.program_form
            form={@program_form}
            enrollment_form={@enrollment_form}
            participant_policy_form={@participant_policy_form}
            uploads={@uploads}
            instructor_options={@instructor_options}
            categories={@categories}
            editing={@editing_program_id != nil}
          />
        <% end %>

        <.programs_table
          programs={@streams.programs}
          staff_options={@staff_options}
          search_query={@search_query}
          selected_staff={@selected_staff}
        />

        <.roster_modal
          :if={@show_roster}
          program_name={@roster_program_name}
          program_id={@roster_program_id}
          entries={@roster_entries}
          invites={@roster_invites}
          active_tab={@roster_tab}
          enrolled_count={@roster_enrolled_count}
          invite_count={@roster_invite_count}
          uploads={@uploads}
          import_errors={@import_errors}
          can_message?={@can_message?}
          invite_mode={@invite_mode}
          single_invite_form={@single_invite_form}
        />

        <.sessions_modal :if={@sessions_modal} modal={@sessions_modal} />
      </div>
    </.pv_dashboard_shell>
    """
  end
end
