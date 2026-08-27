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
  alias KlassHero.Provider.ReadModels.ProgramStaffing
  alias KlassHeroWeb.Helpers.SessionFormHandlers
  alias KlassHeroWeb.Presenters.ProgramPresenter
  alias KlassHeroWeb.Presenters.ProgramStaffingPresenter
  alias KlassHeroWeb.Presenters.StaffMemberPresenter
  alias KlassHeroWeb.Provider.Dashboard.Chrome
  alias KlassHeroWeb.Provider.Dashboard.InviteActions

  require Logger

  @impl true
  def mount(params, _session, socket) do
    provider = socket.assigns.current_scope.provider

    domain_programs = ProgramCatalog.list_programs_for_provider(provider.id)
    enrollment_data = build_enrollment_data(domain_programs)
    programs = to_table_views(domain_programs, enrollment_data, fetch_staffing(domain_programs))

    staff_members = fetch_staff_members(provider.id)
    staff_views = StaffMemberPresenter.to_admin_view_list(staff_members)

    # Current team only: a former member has no active assignment left, so
    # filtering by them would always come back empty — a dead option (#1292).
    staff_options =
      [%{value: "all", label: gettext("All Staff")}] ++
        for member <- staff_views, member.active, do: %{value: member.id, label: member.full_name}

    socket =
      socket
      |> Chrome.assign()
      |> assign(page_title: gettext("My Programs"))
      |> assign(active_nav: :programs)
      |> stream(:programs, programs)
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
      |> assign(staffing_modal: nil)
      |> assign(waivers_modal: nil)
      |> assign(program_form: to_form(ProgramCatalog.new_program_changeset(), as: :program_schema))
      |> assign(enrollment_form: to_form(Enrollment.new_policy_changeset(), as: "enrollment_policy"))
      |> assign(
        participant_policy_form: to_form(Enrollment.new_participant_policy_changeset(), as: "participant_policy")
      )
      |> assign(cap_removal_assessment: :ok)
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
     |> assign(cap_removal_assessment: :ok)
     |> assign(instructor_options: build_instructor_options(socket.assigns.current_scope.provider.id))}
  end

  @impl true
  def handle_event("edit_program", %{"id" => program_id}, socket) do
    provider_id = socket.assigns.current_scope.provider.id

    # program_id is untrusted client input; the scoped getter makes a foreign
    # program unreachable (IDOR guard) rather than fetched and then compared.
    case ProgramCatalog.get_program_for_provider(provider_id, program_id) do
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
           cap_removal_assessment: :ok,
           instructor_options: build_instructor_options(provider_id)
         )}

      {:error, :not_found} ->
        Logger.warning("[ProgramsLive] Program edit attempt for unknown or foreign program",
          program_id: program_id,
          provider_id: provider_id
        )

        {:noreply, put_flash(socket, :error, gettext("Program not found."))}
    end
  end

  @impl true
  def handle_event("view_roster", %{"id" => program_id}, socket) do
    provider_id = socket.assigns.current_scope.provider.id

    # program_id is untrusted client input; the scoped getter makes a foreign
    # program unreachable (IDOR guard).
    case ProgramCatalog.get_program_for_provider(provider_id, program_id) do
      {:ok, program} ->
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

      {:error, :not_found} ->
        Logger.warning("[ProgramsLive] Roster access attempt for unknown or foreign program",
          program_id: program_id,
          provider_id: provider_id
        )

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
       sessions: sessions,
       form: nil
     })}
  end

  @impl true
  def handle_event("close_sessions", _params, socket) do
    {:noreply, assign(socket, :sessions_modal, nil)}
  end

  # The popup already names one program, so the form opens with it filled in and
  # the select replaced by static text. `get_program_for_provider/2` is the
  # tenancy-safe getter, which is also what makes the program's meeting times
  # available to pre-fill — the `provider_programs` projection carries only a name.
  @impl true
  def handle_event("new_session", _params, socket) do
    %{program_id: program_id} = socket.assigns.sessions_modal
    provider_id = socket.assigns.current_scope.provider.id

    case ProgramCatalog.get_program_for_provider(provider_id, program_id) do
      {:ok, program} ->
        form =
          Date.utc_today()
          |> SessionFormHandlers.blank_form(program_id)
          |> SessionFormHandlers.prefill_from_program([program])
          |> to_form(as: :session)

        {:noreply, assign_sessions_modal(socket, form: form)}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, gettext("That program could not be found."))}
    end
  end

  @impl true
  def handle_event("close_new_session", _params, socket) do
    {:noreply, assign_sessions_modal(socket, form: nil)}
  end

  @impl true
  def handle_event("validate_session", %{"session" => params}, socket) do
    # No re-prefill: the program cannot change here, so its defaults were applied
    # once when the form opened and re-applying would fight the provider's edits.
    {:noreply, assign_sessions_modal(socket, form: to_form(params, as: :session))}
  end

  @impl true
  def handle_event("save_session", %{"session" => params}, socket) do
    case SessionFormHandlers.submit(socket.assigns.current_scope, params) do
      {:ok, _session} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Session created successfully"))
         |> reload_sessions_modal()}

      {:error, reason} ->
        if !SessionFormHandlers.user_correctable?(reason) do
          Logger.error(
            "[ProgramsLive.save_session] Failed to create session",
            reason: inspect(reason),
            provider_id: socket.assigns.current_scope.provider.id
          )
        end

        {:noreply, put_flash(socket, :error, SessionFormHandlers.humanize_error(reason))}
    end
  end

  @impl true
  def handle_event("manage_staffing", %{"id" => program_id}, socket) do
    provider_id = socket.assigns.current_scope.provider.id

    # Untrusted client input; the scoped getter makes a foreign program
    # unreachable (IDOR guard), mirroring view_roster/edit_program.
    case ProgramCatalog.get_program_for_provider(provider_id, program_id) do
      {:ok, program} ->
        {:noreply, assign(socket, :staffing_modal, build_staffing_modal(program_id, program.title, provider_id))}

      {:error, :not_found} ->
        Logger.warning("[ProgramsLive] Staffing access attempt for unknown or foreign program",
          program_id: program_id,
          provider_id: provider_id
        )

        {:noreply, put_flash(socket, :error, gettext("Program not found."))}
    end
  end

  @impl true
  def handle_event("close_staffing", _params, socket) do
    {:noreply, assign(socket, :staffing_modal, nil)}
  end

  @impl true
  def handle_event("manage_waivers", %{"id" => program_id}, socket) do
    provider_id = socket.assigns.current_scope.provider.id

    # Same IDOR guard as manage_staffing/view_roster: program_id is client-supplied.
    case ProgramCatalog.get_program_for_provider(provider_id, program_id) do
      {:ok, program} ->
        {:noreply, assign(socket, :waivers_modal, build_waivers_modal(program_id, program.title))}

      {:error, :not_found} ->
        Logger.warning("[ProgramsLive] Waiver access attempt for unknown or foreign program",
          program_id: program_id,
          provider_id: provider_id
        )

        {:noreply, put_flash(socket, :error, gettext("Program not found."))}
    end
  end

  @impl true
  def handle_event("close_waivers", _params, socket) do
    {:noreply, assign(socket, :waivers_modal, nil)}
  end

  @impl true
  def handle_event("edit_waiver", %{"id" => waiver_id}, socket) do
    modal = socket.assigns.waivers_modal
    entry = Enum.find(modal.waivers, &(&1.waiver.id == waiver_id))

    {:noreply,
     assign(socket, :waivers_modal, %{
       modal
       | editing_id: waiver_id,
         form: to_form(%{"body" => entry.version.body}, as: :waiver)
     })}
  end

  @impl true
  def handle_event("cancel_waiver_edit", _params, socket) do
    modal = socket.assigns.waivers_modal
    {:noreply, assign(socket, :waivers_modal, %{modal | editing_id: nil, form: blank_waiver_form()})}
  end

  @impl true
  # Recovery after a reconnect works by replaying the form through phx-change, so this
  # has to write the params back into the assign — a no-op clause would satisfy the
  # markup and still drop what the provider typed.
  def handle_event("validate_waiver", %{"waiver" => params}, socket) do
    modal = socket.assigns.waivers_modal
    {:noreply, assign(socket, :waivers_modal, %{modal | form: to_form(params, as: :waiver)})}
  end

  @impl true
  def handle_event("save_waiver", %{"waiver" => params}, socket) do
    %{program_id: program_id, program_name: program_name, editing_id: editing_id} = socket.assigns.waivers_modal
    provider_id = socket.assigns.current_scope.provider.id

    save_waiver(provider_id, program_id, editing_id, params)
    |> case do
      {:ok, _result} ->
        {:noreply,
         socket
         |> assign(:waivers_modal, build_waivers_modal(program_id, program_name))
         |> put_flash(:info, waiver_saved_message(editing_id))}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, waiver_error_message(reason))
         |> assign(:waivers_modal, %{
           socket.assigns.waivers_modal
           | form: to_form(params, as: :waiver, errors: waiver_form_errors(reason))
         })}
    end
  end

  @impl true
  def handle_event("archive_waiver", %{"id" => waiver_id}, socket) do
    %{program_id: program_id, program_name: program_name} = socket.assigns.waivers_modal
    provider_id = socket.assigns.current_scope.provider.id

    case Enrollment.archive_waiver(provider_id, waiver_id) do
      {:ok, _waiver} ->
        {:noreply,
         socket
         |> assign(:waivers_modal, build_waivers_modal(program_id, program_name))
         |> put_flash(:info, gettext("Waiver retired. Signatures already collected are kept."))}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, gettext("Waiver not found."))}
    end
  end

  @impl true
  def handle_event("assign_staff_member", %{"staff-id" => ""}, socket) do
    {:noreply, put_flash(socket, :error, gettext("Pick a staff member to add."))}
  end

  def handle_event("assign_staff_member", %{"staff-id" => staff_member_id}, socket) do
    %{program_id: program_id} = socket.assigns.staffing_modal
    provider_id = socket.assigns.current_scope.provider.id

    %{provider_id: provider_id, program_id: program_id, staff_member_id: staff_member_id}
    |> Provider.assign_staff_to_program()
    |> case do
      {:ok, _assignment} ->
        {:noreply,
         socket
         |> refresh_staffing_modal()
         |> refresh_program_row(program_id)
         |> put_flash(:info, gettext("Staff member added to the program."))}

      # The picker excludes them, so this is a stale panel (two tabs, back button)
      # rather than user error — re-read so the list stops offering them.
      {:error, :already_assigned} ->
        {:noreply,
         socket
         |> refresh_staffing_modal()
         |> put_flash(:error, gettext("They are already on this program."))}

      {:error, :not_found} ->
        {:noreply, staffing_not_found(socket, "assign", staff_member_id, provider_id)}
    end
  end

  @impl true
  def handle_event("remove_staff_member", %{"staff-id" => staff_member_id}, socket) do
    %{program_id: program_id} = socket.assigns.staffing_modal
    provider_id = socket.assigns.current_scope.provider.id

    case Provider.unassign_staff_from_program(program_id, staff_member_id, provider_id) do
      {:ok, _assignment} ->
        {:noreply,
         socket
         |> refresh_staffing_modal()
         |> refresh_program_row(program_id)
         |> put_flash(:info, gettext("Staff member removed from the program."))}

      {:error, :cannot_unassign_lead} ->
        {:noreply,
         socket
         |> refresh_staffing_modal()
         |> put_flash(
           :error,
           gettext("This person is the lead instructor. Make someone else lead before removing them.")
         )}

      # Already gone — a benign double-click or a second tab, not an error worth
      # a red flash. Re-read so the row disappears.
      {:error, :not_found} ->
        {:noreply, refresh_staffing_modal(socket)}
    end
  end

  @impl true
  def handle_event("promote_to_lead", %{"staff-id" => staff_member_id}, socket) do
    %{program_id: program_id} = socket.assigns.staffing_modal
    provider_id = socket.assigns.current_scope.provider.id

    case Provider.set_lead_instructor(program_id, staff_member_id, provider_id) do
      {:ok, _assignment} ->
        {:noreply,
         socket
         |> refresh_staffing_modal()
         |> refresh_program_row(program_id)
         |> put_flash(:info, gettext("Lead instructor updated."))}

      {:error, :not_found} ->
        {:noreply, staffing_not_found(socket, "promote", staff_member_id, provider_id)}
    end
  end

  @impl true
  def handle_event("send_message_to_parent", %{"parent-user-id" => parent_user_id}, socket) do
    scope = socket.assigns.current_scope
    provider_id = scope.provider.id
    program_id = socket.assigns.roster_program_id

    # parent_user_id is untrusted; re-checked here so the flash lands on the roster
    # rather than bouncing the provider to the inbox, and again on the compose mount.
    if Messaging.can_message_parent?(scope, provider_id, program_id, parent_user_id) do
      {:noreply,
       push_navigate(socket,
         to: ~p"/provider/messages/new?provider_id=#{provider_id}&user_id=#{parent_user_id}&program_id=#{program_id}"
       )}
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
    {:noreply, invite_action(&InviteActions.resend/4, invite_id, socket)}
  end

  @impl true
  def handle_event("delete_invite", %{"id" => invite_id}, socket) do
    {:noreply, invite_action(&InviteActions.delete/4, invite_id, socket)}
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
  # sobelow_skip ["Traversal.FileModule"]
  # The path comes from consume_uploaded_entries — a LiveView-generated temp file, not
  # from the client. The uploader controls the filename, never this path.
  def handle_event("import_csv", _params, socket) do
    provider_id = socket.assigns.current_scope.provider.id
    program_id = socket.assigns.roster_program_id

    # Wrap File.read/1 result so consume_uploaded_entries doesn't unwrap the inner {:ok, binary}.
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
       participant_policy_form: to_form(Enrollment.new_participant_policy_changeset(), as: "participant_policy"),
       cap_removal_assessment: :ok
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
     |> assign(participant_policy_form: to_form(participant_policy_changeset, as: "participant_policy"))
     |> assign(cap_removal_assessment: assess_cap_removal(socket, enrollment_params))}
  end

  @impl true
  def handle_event("save_program", %{"program_schema" => params} = all_params, socket) do
    provider = socket.assigns.current_scope.provider

    cover_result = upload_program_cover(socket, provider.id)

    attrs =
      %{
        provider_id: provider.id,
        title: params["title"],
        subtitle: presence(params["subtitle"]),
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

    with {:ok, instructor_id} <- resolve_instructor(program_params["instructor_id"], socket),
         {:ok, program} <- ProgramCatalog.create_program(attrs) do
      :ok = apply_lead_instructor(program.id, instructor_id, socket.assigns.current_scope.provider.id)
      policy_result = set_enrollment_policy_on_create(program.id, enrollment_params)
      participant_result = set_participant_policy_on_create(program.id, participant_policy_params)
      capacity = resolve_capacity(policy_result, enrollment_params)

      new_enrollment_data = %{
        program.id => %{enrolled: 0, capacity: capacity}
      }

      {:noreply,
       socket
       |> flash_for_save(:created,
         enrollment_policy: policy_result,
         participant_policy: participant_result
       )
       |> maybe_flash_cover_warning(cover_result)
       |> reveal_program_row(program, new_enrollment_data)
       |> assign(
         show_program_form: false,
         editing_program_id: nil,
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
    provider_id = socket.assigns.current_scope.provider.id

    with {:ok, instructor_id} <- resolve_instructor(program_params["instructor_id"], socket),
         {:ok, updated} <- ProgramCatalog.update_program(provider_id, program_id, attrs) do
      :ok = apply_lead_instructor(program_id, instructor_id, provider_id)

      case set_enrollment_policy_on_update(program_id, enrollment_params) do
        {:error, {:cap_removal_blocked, active}} ->
          halt_for_cap_acknowledgement(socket, active)

        policy_result ->
          participant_result = set_participant_policy_on_update(program_id, participant_policy_params)

          capacity = resolve_capacity(policy_result, enrollment_params)
          active_counts = Enrollment.count_active_enrollments_batch([program_id])
          enrolled = Map.get(active_counts, program_id, 0)
          enrollment_data = %{program_id => %{enrolled: enrolled, capacity: capacity}}

          {:noreply,
           socket
           |> flash_for_save(:updated,
             enrollment_policy: policy_result,
             participant_policy: participant_result
           )
           |> maybe_flash_cover_warning(cover_result)
           |> sync_program_row(updated, enrollment_data)
           |> assign(
             show_program_form: false,
             editing_program_id: nil,
             cap_removal_assessment: :ok,
             enrollment_form: to_form(Enrollment.new_policy_changeset(), as: "enrollment_policy"),
             participant_policy_form: to_form(Enrollment.new_participant_policy_changeset(), as: "participant_policy")
           )}
      end
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

  # Both invite actions reload the same thing — the open roster's invites — so the
  # only part that varies is which InviteActions function runs.
  defp invite_action(action, invite_id, socket) do
    program_id = socket.assigns.roster_program_id
    provider_id = socket.assigns.current_scope.provider.id

    action.(socket, invite_id, provider_id, &refresh_invites_silent(&1, program_id))
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

  defp fetch_staff_members(provider_id) do
    {:ok, members} = Provider.list_staff_members(provider_id)
    members
  end

  # Filters run over the DOMAIN programs and their staffing read-model, then the
  # survivors are presented — never the other way round. Filtering presenter
  # output is what made the staff filter match on the rendered lead alone, so a
  # non-lead staff member found none of their programs (#1310).
  defp reset_programs_stream(socket) do
    provider_id = socket.assigns.current_scope.provider.id
    domain_programs = ProgramCatalog.list_programs_for_provider(provider_id)
    staffing = fetch_staffing(domain_programs)

    filtered =
      domain_programs
      |> filter_by_search(socket.assigns.search_query)
      |> filter_by_staff(staffing, socket.assigns.selected_staff)

    programs = to_table_views(filtered, build_enrollment_data(filtered), staffing)

    stream(socket, :programs, programs, reset: true)
  end

  # One query for the whole table's staffing, so neither rendering nor filtering
  # N+1s across programs.
  defp fetch_staffing(domain_programs) do
    domain_programs
    |> Enum.map(& &1.id)
    |> Provider.list_program_staffing()
  end

  defp to_table_views(domain_programs, enrollment_data, staffing) do
    Enum.map(
      domain_programs,
      &ProgramPresenter.to_table_view(&1, enrollment_data, Map.get(staffing, &1.id))
    )
  end

  # Two facade reads joined by a presenter, the same shape ProgramDetailLive uses
  # for the public "Meet the Heroes" section — `is_lead_instructor` on the
  # assignment is the single source of truth for who leads.
  # Rebuilt from the context after every write rather than patched in place — the panel is
  # small, and a stale local copy is how a "current version" display drifts from the row a
  # signature will actually bind to.
  defp build_waivers_modal(program_id, program_name) do
    %{
      program_id: program_id,
      program_name: program_name,
      waivers: Enrollment.list_program_waivers(program_id),
      editing_id: nil,
      form: blank_waiver_form()
    }
  end

  defp blank_waiver_form do
    to_form(%{"title" => "", "body" => "", "required" => "true"}, as: :waiver)
  end

  defp save_waiver(provider_id, _program_id, waiver_id, %{"body" => body}) when is_binary(waiver_id) do
    Enrollment.publish_waiver_version(provider_id, waiver_id, body)
  end

  defp save_waiver(provider_id, program_id, nil, params) do
    Enrollment.create_waiver(provider_id, %{
      program_id: program_id,
      title: params["title"],
      body: params["body"],
      required: params["required"] == "true"
    })
  end

  defp waiver_saved_message(nil), do: gettext("Waiver added.")
  defp waiver_saved_message(_editing_id), do: gettext("New version published. It applies to future enrolments.")

  defp waiver_error_message(:not_found), do: gettext("Program not found.")
  defp waiver_error_message(_reason), do: gettext("Check the waiver details and try again.")

  # Domain validators return a keyword list of {field, message}; changesets carry their own.
  defp waiver_form_errors(errors) when is_list(errors) do
    for {field, message} <- errors, do: {field, {message, []}}
  end

  defp waiver_form_errors(%Ecto.Changeset{} = changeset), do: changeset.errors
  defp waiver_form_errors(_reason), do: []

  defp assign_sessions_modal(socket, updates) do
    assign(socket, :sessions_modal, Enum.into(updates, socket.assigns.sessions_modal))
  end

  # The new row reaches `provider_session_details` through session_created and an
  # Oban job, so this re-read can legitimately come back without it. That is the
  # projection's normal lag, not a failure — the row appears on the next open. An
  # optimistic insert here would be a second writer to a read table the projection
  # owns, which is the drift #1321 deleted.
  defp reload_sessions_modal(socket) do
    %{program_id: program_id} = socket.assigns.sessions_modal
    provider_id = socket.assigns.current_scope.provider.id

    assign_sessions_modal(socket,
      form: nil,
      sessions: Provider.list_program_sessions(provider_id, program_id)
    )
  end

  defp build_staffing_modal(program_id, program_name, provider_id) do
    lead_id =
      case Provider.get_lead_instructor(program_id) do
        %{id: id} -> id
        nil -> nil
      end

    members =
      program_id
      |> Provider.list_active_staff_for_program()
      |> ProgramStaffingPresenter.for_panel(lead_id)

    assignable =
      provider_id
      |> Provider.list_assignable_staff_for_program(program_id)
      |> staff_to_options()

    %{
      program_id: program_id,
      program_name: program_name,
      members: members,
      assignable_options: assignable
    }
  end

  # Every mutation re-reads rather than patching the assign in place: the context
  # owns who is on the program and who leads it, so the panel asks it again.
  defp refresh_staffing_modal(socket) do
    %{program_id: program_id, program_name: program_name} = socket.assigns.staffing_modal
    provider_id = socket.assigns.current_scope.provider.id

    assign(socket, :staffing_modal, build_staffing_modal(program_id, program_name, provider_id))
  end

  # Every staffing change reaches the table now that the column renders the whole
  # roster — adding or removing a non-lead moves the headcount, so those paths
  # refresh the row too, not just promotion.
  defp refresh_program_row(socket, program_id) do
    provider_id = socket.assigns.current_scope.provider.id

    case ProgramCatalog.get_program_for_provider(provider_id, program_id) do
      {:ok, program} ->
        sync_program_row(socket, program, build_enrollment_data([program]), fetch_program_staffing(program_id))

      {:error, :not_found} ->
        socket
    end
  end

  # The three write paths differ only in where the enrollment numbers come from:
  # the save paths hand-build them so a rejected capacity blanks the cell instead
  # of showing the surviving old policy, while the staffing panel re-reads. That
  # decision stays with each caller; everything after it is this one rebuild (#1307).
  #
  # The panel path already holds the staffing it filtered on, so it passes it in
  # rather than paying for the read twice.
  #
  # Whether the row belongs in the table at all is *not* a caller's decision: the
  # table is filtered, so a write that ignores the filter shows a row contradicting
  # it. Every path lands here, so a fourth one is correct without knowing that (#1346).
  defp sync_program_row(socket, program, enrollment_data) do
    sync_program_row(socket, program, enrollment_data, fetch_program_staffing(program.id))
  end

  defp sync_program_row(socket, program, enrollment_data, staffing) do
    if row_matches_filters?(socket, program, staffing) do
      stream_insert(socket, :programs, ProgramPresenter.to_table_view(program, enrollment_data, staffing))
    else
      stream_delete(socket, :programs, %{id: program.id})
    end
  end

  # A program the provider just made is the one row they are certainly looking
  # for, so a filter that would hide it yields rather than the row — the
  # alternative is a save that visibly does nothing (#1346).
  #
  # Both axes yield together, even when only one of them hides the row: clearing
  # per-axis would branch on every combination to spare a search term the row
  # still matched. Deliberate, and pinned by a test.
  defp reveal_program_row(socket, program, enrollment_data) do
    staffing = fetch_program_staffing(program.id)

    if row_matches_filters?(socket, program, staffing) do
      sync_program_row(socket, program, enrollment_data, staffing)
    else
      # The re-stream cannot carry the new row: it reads the `program_listings`
      # projection, which has not caught up with a program created a moment ago.
      # Only the domain struct the write returned can show it, so the row is
      # inserted on top of the freshly unfiltered table.
      socket
      |> assign(search_query: "", selected_staff: "all")
      |> reset_programs_stream()
      |> sync_program_row(program, enrollment_data, staffing)
    end
  end

  defp fetch_program_staffing(program_id) do
    Map.get(Provider.list_program_staffing([program_id]), program_id)
  end

  # Asks the table's own filters about one row, so "what the list shows" and
  # "what a row write shows" cannot drift apart — the drift is what let a save
  # insert a row contradicting the active filter (#1346).
  defp row_matches_filters?(socket, program, staffing) do
    [program]
    |> filter_by_search(socket.assigns.search_query)
    |> filter_by_staff(%{program.id => staffing}, socket.assigns.selected_staff)
    |> Enum.any?()
  end

  defp staffing_not_found(socket, action, staff_member_id, provider_id) do
    Logger.warning("[ProgramsLive] Staffing #{action} for unknown or foreign staff member",
      staff_member_id: staff_member_id,
      provider_id: provider_id
    )

    socket
    |> refresh_staffing_modal()
    |> put_flash(:error, gettext("That staff member could not be found."))
  end

  defp build_enrollment_data(domain_programs) do
    program_ids = Enum.map(domain_programs, & &1.id)
    Enrollment.get_enrollment_summary_batch(program_ids)
  end

  defp filter_by_search(programs, ""), do: programs

  defp filter_by_search(programs, query) do
    query_lower = String.downcase(query)

    Enum.filter(programs, fn program ->
      String.contains?(String.downcase(program.title), query_lower)
    end)
  end

  defp filter_by_staff(programs, _staffing, "all"), do: programs

  # Matches anyone active on the program, lead or not — the read-model owns that
  # definition, so the column's rendering can change without moving it.
  defp filter_by_staff(programs, staffing, staff_id) do
    Enum.filter(programs, fn program ->
      ProgramStaffing.staffed_by?(Map.get(staffing, program.id), staff_id)
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

  # Validates the instructor exists, belongs to this provider (IDOR guard), and is
  # still employed (#1306) — the pre-write gate that keeps apply_lead_instructor's
  # bang-match safe. It must refuse on exactly the conditions set_lead_instructor/3
  # refuses on, or the bang below matches an {:error, :not_found} and crashes.
  defp resolve_instructor(id, _socket) when id in [nil, ""], do: {:ok, nil}

  defp resolve_instructor(instructor_id, socket) do
    provider_id = socket.assigns.current_scope.provider.id

    case Provider.get_active_staff_member(instructor_id, provider_id) do
      {:ok, _staff} ->
        {:ok, instructor_id}

      _not_found_foreign_or_deactivated ->
        Logger.warning("Instructor not found, not owned by provider, or deactivated during program save",
          instructor_id: instructor_id,
          provider_id: provider_id
        )

        {:error, :instructor_not_found}
    end
  end

  # Persists the lead choice on program_staff_assignments (single source of truth).
  # Blank pick clears the lead; id already ownership-validated by resolve_instructor/2.
  # provider_id re-threaded so the context re-checks too (defence in depth).
  defp apply_lead_instructor(program_id, nil, provider_id), do: Provider.clear_lead_instructor(program_id, provider_id)

  defp apply_lead_instructor(program_id, instructor_id, provider_id) do
    {:ok, _assignment} = Provider.set_lead_instructor(program_id, instructor_id, provider_id)
    :ok
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

  # Skip the upsert on create when both limits are empty — avoid storing an all-nil row
  # for a program that never specified any.
  defp set_enrollment_policy_on_create(program_id, params) do
    min = parse_integer(params["min_enrollment"])
    max = parse_integer(params["max_enrollment"])

    if is_nil(min) and is_nil(max) do
      :ok
    else
      save_enrollment_policy(
        %{program_id: program_id, min_enrollment: min, max_enrollment: max},
        program_id
      )
    end
  end

  # Trigger: existing program edit — must allow clearing previously stored limits
  # Why: the form is prefilled from the stored policy, so short-circuiting on all-empty
  #   would read a deliberate clear as an absence and leave stale values (issue #1370,
  #   the same shape #795 fixed for the participant policy)
  # Outcome: always upsert, carrying explicit nils so on_conflict replaces stored values
  defp set_enrollment_policy_on_update(program_id, params) do
    save_enrollment_policy(
      %{
        program_id: program_id,
        min_enrollment: parse_integer(params["min_enrollment"]),
        max_enrollment: parse_integer(params["max_enrollment"]),
        acknowledge_cap_removal: params["acknowledge_cap_removal"] == "true"
      },
      program_id
    )
  end

  defp save_enrollment_policy(attrs, program_id) do
    case Enrollment.set_enrollment_policy(attrs) do
      {:ok, _policy} ->
        :ok

      # Not a failure to report and move on from — the provider is being asked a
      # question, so the reason travels intact and the caller reopens the form.
      {:error, {:cap_removal_blocked, _active} = reason} ->
        {:error, reason}

      # Program already created — don't roll back, propagate error to show a warning flash.
      {:error, reason} ->
        Logger.warning("[Provider.ProgramsLive] Failed to save enrollment policy",
          program_id: program_id,
          reason: inspect(reason)
        )

        {:error, :enrollment_policy_failed}
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

  # The program row is already written by the time the policy sub-writes run, so a
  # rejected one is reported, never rolled back. Flash is keyed by kind, so a second
  # put_flash of the same kind erases the first — every failure merges into ONE
  # :warning, which also keeps it clear of a real :error (#1345).
  defp flash_for_save(socket, action, results) do
    failed_sources = for {source, {:error, _reason}} <- results, do: source

    case failed_sources do
      [] ->
        socket
        |> clear_flash(:error)
        |> clear_flash(:warning)
        |> put_flash(:info, save_success_message(action))

      _ ->
        put_flash(socket, :warning, save_failure_message(action, failed_sources))
    end
  end

  # Asked of Enrollment rather than decided here, so the warning the provider sees and
  # the rule the write enforces come from one predicate (see assess_capacity_change/2).
  defp assess_cap_removal(%{assigns: %{editing_program_id: nil}}, _params), do: :ok

  defp assess_cap_removal(%{assigns: %{editing_program_id: program_id}}, params) do
    Enrollment.assess_capacity_change(program_id, parse_integer(params["max_enrollment"]))
  end

  # The backstop, not the everyday path: the acknowledgement checkbox is `required`, so
  # this is reached when a booking lands while the form sits open (or a crafted submit).
  # The form stays open carrying the warning, so the answer is one tick away.
  defp halt_for_cap_acknowledgement(socket, active) do
    {:noreply,
     socket
     |> assign(cap_removal_assessment: {:cap_removal, active})
     |> put_flash(:warning, cap_removal_message(active))}
  end

  defp save_success_message(:created), do: gettext("Program created successfully.")
  defp save_success_message(:updated), do: gettext("Program updated successfully.")

  defp save_failure_message(:created, [:enrollment_policy]) do
    gettext("Program created, but enrollment capacity could not be saved. Edit the program to retry.")
  end

  defp save_failure_message(:updated, [:enrollment_policy]) do
    gettext("Program updated, but the enrollment capacity was rejected. The previous limits still apply.")
  end

  # A rejected participant policy is a should-never-happen (the form only submits
  # shapes the changeset accepts), so it shares one message rather than earning its own.
  defp save_failure_message(:created, _failed_sources) do
    gettext("Program created, but some settings could not be saved. Please review the program's limits.")
  end

  defp save_failure_message(:updated, _failed_sources) do
    gettext("Program updated, but some settings could not be saved. Please review the program's limits.")
  end

  defp lead_instructor_id(program_id) do
    case Provider.get_lead_instructor(program_id) do
      %{id: id} -> id
      nil -> nil
    end
  end

  defp program_to_form_params(program) do
    %{
      "title" => program.title,
      "subtitle" => program.subtitle,
      "description" => program.description,
      "category" => program.category,
      "price" => nil_safe(program.price, &Decimal.to_string/1),
      "location" => program.location,
      "instructor_id" => lead_instructor_id(program.id),
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
            cap_removal_assessment={@cap_removal_assessment}
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

        <.staffing_modal :if={@staffing_modal} modal={@staffing_modal} />

        <.waivers_modal :if={@waivers_modal} modal={@waivers_modal} />
      </div>
    </.pv_dashboard_shell>
    """
  end
end
