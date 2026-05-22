defmodule KlassHeroWeb.Provider.DashboardLive do
  @moduledoc """
  Provider dashboard LiveView with tab-based navigation.

  Sections:
  - Overview: Stats, business profile, verification badges
  - Team & Profiles: Team member management
  - My Programs: Program inventory and management
  - Edit: Profile editing with logo/verification doc uploads
  """
  use KlassHeroWeb, :live_view

  import KlassHeroWeb.ProviderComponents

  alias KlassHero.Accounts.Scope
  alias KlassHero.Enrollment
  alias KlassHero.Messaging
  alias KlassHero.ProgramCatalog
  alias KlassHero.ProgramCatalog.Domain.ReadModels.ProgramListing
  alias KlassHero.Provider
  alias KlassHero.Provider.Domain.Models.PayRate
  alias KlassHero.Provider.Domain.Models.ProviderProfile
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias KlassHero.Shared.Entitlements
  alias KlassHero.Shared.Storage
  alias KlassHeroWeb.Helpers.TaskHelpers
  alias KlassHeroWeb.Presenters.ProgramPresenter
  alias KlassHeroWeb.Presenters.ProviderPresenter
  alias KlassHeroWeb.Presenters.StaffMemberPresenter
  alias KlassHeroWeb.Theme

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    case socket.assigns.current_scope.provider do
      nil ->
        Logger.warning("Provider dashboard accessed without provider profile",
          user_id: socket.assigns.current_scope.user.id
        )

        {:ok, redirect(socket, to: ~p"/")}

      provider_profile ->
        business = ProviderPresenter.to_business_view(provider_profile)

        # Trigger: to_business_view defaults verification_status to :not_started
        # Why: full docs-based derivation happens in handle_params(:overview),
        #      but other tabs need a baseline so the "New Program" button gating works
        # Outcome: verified providers get :verified immediately; detail refinement on overview tab
        business =
          if provider_profile.verified do
            %{business | verification_status: :verified}
          else
            business
          end

        # Load programs and staff in parallel — both are independent DB queries
        programs_task =
          Task.Supervisor.async_nolink(KlassHero.TaskSupervisor, fn ->
            ProgramCatalog.list_programs_for_provider(provider_profile.id)
          end)

        staff_task =
          Task.Supervisor.async_nolink(KlassHero.TaskSupervisor, fn ->
            fetch_staff_members(provider_profile.id)
          end)

        domain_programs =
          TaskHelpers.safe_await(programs_task, [], label: "Provider.DashboardLive.programs")

        enrollment_data = build_enrollment_data(domain_programs)
        programs = Enum.map(domain_programs, &ProgramPresenter.to_table_view(&1, enrollment_data))

        staff_members =
          TaskHelpers.safe_await(staff_task, [], label: "Provider.DashboardLive.staff")

        staff_views = StaffMemberPresenter.to_admin_view_list(staff_members)
        programs_count = length(programs)
        self_posted_count = ProgramCatalog.count_self_posted_programs(provider_profile.id)

        # Build staff filter options from real data
        staff_options =
          [%{value: "all", label: gettext("All Staff")}] ++
            Enum.map(staff_views, &%{value: &1.id, label: &1.full_name})

        # Trigger: uploads registered unconditionally in mount
        # Why: allow_upload must happen once; registering in handle_params
        #      would cause double-registration errors when patching between actions
        # Outcome: upload channels are inert on non-edit tabs (no UI renders them)
        socket =
          socket
          |> assign(page_title: gettext("Provider Dashboard"))
          |> assign(business: business)
          |> assign(:profile_draft?, ProviderProfile.draft?(provider_profile))
          |> assign(:dual_role?, Scope.dual_role?(socket.assigns.current_scope))
          |> stream(:team_members, staff_views)
          |> update_staff_count(length(staff_views))
          |> stream(:programs, programs)
          |> assign(programs_count: programs_count)
          |> update_program_slots(self_posted_count)
          |> assign(staff_options: staff_options)
          |> assign(search_query: "")
          |> assign(selected_staff: "all")
          |> assign(show_staff_form: false, editing_staff_id: nil)
          |> assign(staff_form: to_form(Provider.new_staff_member_changeset()))
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
          |> assign(:sessions_modal, nil)
          |> assign(program_form: to_form(ProgramCatalog.new_program_changeset()))
          |> assign(enrollment_form: to_form(Enrollment.new_policy_changeset(), as: "enrollment_policy"))
          |> assign(
            participant_policy_form: to_form(Enrollment.new_participant_policy_changeset(), as: "participant_policy")
          )
          |> assign(instructor_options: build_instructor_options(staff_members))
          |> assign(categories: ProgramCatalog.program_categories())
          |> assign(document_types: Provider.valid_document_types())
          |> assign(total_sessions_completed: 0)
          |> assign(enrolled_total: 0)
          |> assign(pending_requests: [])
          |> assign(pending_enrollments: [])
          |> assign(top_programs: [])
          |> allow_upload(:logo,
            accept: ~w(.jpg .jpeg .png .webp),
            max_entries: 1,
            max_file_size: 2_000_000
          )
          |> allow_upload(:verification_doc,
            accept: ~w(.pdf .jpg .jpeg .png),
            max_entries: 1,
            max_file_size: 10_000_000
          )
          |> allow_upload(:headshot,
            accept: ~w(.jpg .jpeg .png .webp),
            max_entries: 1,
            max_file_size: 1_000_000
          )
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

        {:ok, socket}
    end
  end

  @impl true
  def handle_params(_params, _uri, %{assigns: %{live_action: :edit}} = socket) do
    provider = socket.assigns.current_scope.provider

    changeset = Provider.change_provider_profile(provider)

    docs = fetch_verification_docs(provider.id)

    socket =
      socket
      |> assign(page_title: gettext("Edit Profile"))
      |> assign(active_nav: :home)
      |> assign(form: to_form(changeset))
      |> assign(doc_type: "business_registration")
      |> stream(:verification_docs, docs, reset: true, dom_id: &"vdoc-#{&1.id}")

    {:noreply, socket}
  end

  @impl true
  def handle_params(_params, _uri, %{assigns: %{live_action: :overview}} = socket) do
    provider = socket.assigns.current_scope.provider

    # Trigger: overview tab needs verification status derived from documents
    # Why: provider.verified alone is boolean; documents give granular status
    # Outcome: business map gets :verification_status (:verified/:pending/:rejected/:not_started)
    docs = fetch_verification_docs(provider.id)

    verification_status =
      ProviderPresenter.verification_status_from_docs(provider.verified, docs)

    business = %{socket.assigns.business | verification_status: verification_status}

    total_sessions = Provider.get_total_session_count(provider.id)

    program_listings = ProgramCatalog.list_programs_for_provider(provider.id)
    program_ids = Enum.map(program_listings, & &1.id)

    enrollment_counts = Enrollment.count_active_enrollments_batch(program_ids)
    enrolled_total = enrollment_counts |> Map.values() |> Enum.sum()

    pending_requests = load_pending_requests(program_ids)
    pending_enrollments = Enrollment.list_pending_enrollments_for_provider(program_ids)
    top_programs = build_top_programs(program_listings, enrollment_counts)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(KlassHero.PubSub, "provider:#{provider.id}:stats_updated")

      Phoenix.PubSub.subscribe(
        KlassHero.PubSub,
        Enrollment.provider_scoped_topic(:enrollment_confirmed, provider.id)
      )
    end

    {:noreply,
     socket
     |> assign(active_nav: :home)
     |> assign(business: business)
     |> assign(total_sessions_completed: total_sessions)
     |> assign(enrolled_total: enrolled_total)
     |> assign(pending_requests: pending_requests)
     |> assign(pending_enrollments: pending_enrollments)
     |> assign(top_programs: top_programs)}
  end

  @impl true
  def handle_params(_params, _uri, %{assigns: %{live_action: :team}} = socket) do
    provider = socket.assigns.current_scope.provider

    staff_members = fetch_staff_members(provider.id)
    staff_views = StaffMemberPresenter.to_admin_view_list(staff_members)

    {:noreply,
     socket
     |> assign(active_nav: :home)
     |> stream(:team_members, staff_views, reset: true)
     |> update_staff_count(length(staff_members))}
  end

  @impl true
  def handle_params(_params, _uri, %{assigns: %{live_action: :programs}} = socket) do
    {:noreply,
     socket
     |> assign(active_nav: :programs)
     |> refresh_staff_options()
     |> reset_programs_stream()}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, active_nav: :home)}
  end

  # ============================================================================
  # PubSub Handlers
  # ============================================================================

  @impl true
  def handle_info(:session_stats_updated, %{assigns: %{live_action: :overview}} = socket) do
    provider = socket.assigns.current_scope.provider
    new_count = Provider.get_total_session_count(provider.id)

    if new_count == socket.assigns.total_sessions_completed do
      {:noreply, socket}
    else
      {:noreply, assign(socket, total_sessions_completed: new_count)}
    end
  end

  @impl true
  def handle_info({:domain_event, %DomainEvent{event_type: :enrollment_confirmed}}, socket) do
    {:noreply, refresh_pending_enrollments(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  # ============================================================================
  # Pending Enrollment Events
  # ============================================================================

  @impl true
  def handle_event("approve_enrollment", %{"id" => enrollment_id}, socket) do
    provider_id = socket.assigns.current_scope.provider.id

    case Enrollment.confirm_enrollment(%{
           enrollment_id: enrollment_id,
           provider_id: provider_id
         }) do
      {:ok, _enrollment} ->
        # No refresh here — :enrollment_confirmed loopback drives it (handle_info/2).
        {:noreply, put_flash(socket, :info, gettext("Enrollment approved"))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("Not allowed to approve this enrollment"))}

      {:error, :invalid_status_transition} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Enrollment is not pending"))
         |> refresh_pending_enrollments()}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, gettext("Enrollment not found"))}

      {:error, reason} ->
        Logger.error("[Dashboard.approve_enrollment] Failed",
          enrollment_id: enrollment_id,
          provider_id: provider_id,
          reason: inspect(reason)
        )

        {:noreply, put_flash(socket, :error, gettext("Failed to approve"))}
    end
  end

  # ============================================================================
  # Staff Member CRUD Events
  # ============================================================================

  @impl true
  def handle_event("add_member", _params, socket) do
    {:noreply,
     socket
     |> assign(show_staff_form: true, editing_staff_id: nil)
     |> assign(staff_form: to_form(Provider.new_staff_member_changeset()))}
  end

  @impl true
  def handle_event("edit_member", %{"id" => staff_id}, socket) do
    case Provider.get_staff_member(staff_id) do
      {:ok, staff} ->
        changeset = Provider.change_staff_member(staff)

        {:noreply,
         socket
         |> assign(show_staff_form: true, editing_staff_id: staff_id)
         |> assign(staff_form: to_form(changeset))}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, gettext("Staff member not found."))}
    end
  end

  @impl true
  def handle_event("close_staff_form", _params, socket) do
    {:noreply, assign(socket, show_staff_form: false)}
  end

  @impl true
  def handle_event("validate_staff", %{"staff_member_schema" => params}, socket) do
    params = normalize_staff_form_params(params)

    changeset =
      case socket.assigns.editing_staff_id do
        nil ->
          Provider.new_staff_member_changeset(params)

        staff_id ->
          # Trigger: staff member may have been deleted between form open and keystroke
          # Why: bare match on {:ok, _} would crash if member no longer exists
          # Outcome: fall back to new changeset, preserving user's typed data
          case Provider.get_staff_member(staff_id) do
            {:ok, staff} ->
              Provider.change_staff_member(staff, params)

            {:error, :not_found} ->
              Provider.new_staff_member_changeset(params)
          end
      end

    {:noreply, assign(socket, staff_form: to_form(Map.put(changeset, :action, :validate)))}
  end

  @impl true
  def handle_event("save_staff", %{"staff_member_schema" => params}, socket) do
    provider = socket.assigns.current_scope.provider

    # Trigger: headshot upload may be present or absent
    # Why: staff member can be saved without a headshot
    # Outcome: include headshot_url in attrs if upload succeeded
    headshot_result = upload_headshot(socket, provider.id)

    case socket.assigns.editing_staff_id do
      nil -> save_new_staff(socket, params, provider, headshot_result)
      staff_id -> save_existing_staff(socket, params, staff_id, headshot_result)
    end
  end

  @impl true
  def handle_event("delete_member", %{"id" => staff_id}, socket) do
    case Provider.delete_staff_member(staff_id) do
      :ok ->
        {:noreply,
         socket
         |> stream_delete_by_dom_id(:team_members, "team_members-#{staff_id}")
         |> update_staff_count(max(0, socket.assigns.staff_count - 1))
         |> clear_flash(:error)
         |> put_flash(:info, gettext("Team member removed."))}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, gettext("Staff member not found."))}
    end
  end

  @impl true
  def handle_event("resend_invitation", %{"id" => staff_member_id}, socket) do
    case Provider.resend_staff_invitation(staff_member_id) do
      {:ok, updated, _raw_token} ->
        staff_view = StaffMemberPresenter.to_admin_view(updated)

        {:noreply,
         socket
         |> stream_insert(:team_members, staff_view)
         |> put_flash(:info, gettext("Invitation resent successfully."))}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, gettext("Staff member not found."))}

      {:error, :invalid_invitation_transition} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("This invitation cannot be resent in its current state.")
         )}

      {:error, reason} ->
        Logger.warning("[DashboardLive] Resend invitation failed",
          staff_member_id: staff_member_id,
          reason: inspect(reason)
        )

        {:noreply, put_flash(socket, :error, gettext("Failed to resend invitation. Please try again."))}
    end
  end

  # ============================================================================
  # Edit Profile Events
  # ============================================================================

  @impl true
  def handle_event("validate_profile", %{"provider_profile_schema" => params}, socket) do
    provider = socket.assigns.current_scope.provider
    changeset = Provider.change_provider_profile(provider, params)

    {:noreply, assign(socket, form: to_form(Map.put(changeset, :action, :validate)))}
  end

  @impl true
  def handle_event("save_profile", %{"provider_profile_schema" => params}, socket) do
    provider = socket.assigns.current_scope.provider
    Logger.info("save_profile: starting", provider_id: provider.id)

    # Trigger: logo upload may succeed, be absent, or fail
    # Why: provider can save without a new logo, but upload failures must not be silently ignored
    # Outcome: :upload_error aborts save; :no_upload proceeds without logo; {:ok, url} includes logo
    logo_result = upload_logo(socket, provider.id)
    Logger.info("save_profile: logo upload result", provider_id: provider.id, result: logo_result)

    case logo_result do
      :upload_error ->
        {:noreply, put_flash(socket, :error, gettext("Logo upload failed. Please try again."))}

      logo_result ->
        attrs = %{description: params["description"]}

        attrs =
          case logo_result do
            {:ok, url} -> Map.put(attrs, :logo_url, url)
            :no_upload -> attrs
          end

        case Provider.update_provider_profile(provider.id, attrs) do
          {:ok, _updated} ->
            {:noreply,
             socket
             |> put_flash(:info, gettext("Profile updated successfully."))
             |> push_navigate(to: ~p"/provider/dashboard")}

          {:error, {:validation_error, _errors}} ->
            {:noreply, put_flash(socket, :error, gettext("Please fix the errors below."))}

          {:error, :not_found} ->
            {:noreply,
             socket
             |> put_flash(:error, gettext("Provider profile not found."))
             |> push_navigate(to: ~p"/")}

          {:error, changeset} ->
            {:noreply, assign(socket, form: to_form(changeset))}
        end
    end
  end

  @impl true
  def handle_event("upload_verification_doc", _params, socket) do
    provider = socket.assigns.current_scope.provider
    doc_type = socket.assigns.doc_type

    case safe_consume_uploaded_entries(socket, :verification_doc, fn %{path: path}, entry ->
           try do
             # sobelow_skip ["Traversal.FileModule"]
             file_binary = File.read!(path)

             case Provider.submit_verification_document(%{
                    provider_profile_id: provider.id,
                    document_type: doc_type,
                    file_binary: file_binary,
                    original_filename: entry.client_name,
                    content_type: entry.client_type
                  }) do
               {:ok, doc} -> {:ok, doc}
               {:error, reason} -> {:postpone, reason}
             end
           catch
             kind, reason ->
               Logger.error("Verification doc upload failed",
                 provider_id: provider.id,
                 doc_type: doc_type,
                 kind: kind,
                 error: inspect(reason)
               )

               {:error, :upload_exception}
           end
         end) do
      {:error, :upload_channel_died} ->
        {:noreply, put_flash(socket, :error, gettext("Upload connection lost. Please try again."))}

      # consume_uploaded_entries unwraps {:ok, value} → value
      {:ok, [%{} = doc]} ->
        {:noreply,
         socket
         |> stream_insert(:verification_docs, doc, dom_id: &"vdoc-#{&1.id}")
         |> put_flash(:info, gettext("Document uploaded successfully."))}

      {:ok, other} ->
        Logger.error("Verification document upload failed",
          provider_id: provider.id,
          doc_type: doc_type,
          errors: inspect(other)
        )

        {:noreply, put_flash(socket, :error, gettext("Failed to upload document."))}
    end
  end

  @impl true
  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_doc_type", %{"doc_type" => doc_type}, socket) do
    {:noreply, assign(socket, doc_type: doc_type)}
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref, "upload" => upload_name}, socket) do
    {:noreply, cancel_upload(socket, String.to_existing_atom(upload_name), ref)}
  end

  # ============================================================================
  # Program Creation Events
  # ============================================================================

  @impl true
  def handle_event("add_program", _params, socket) do
    # Trigger: header CTA fires from any tab, but the program form lives in
    # the Programs section. Patch over so the form is actually visible.
    {:noreply,
     socket
     |> assign(show_program_form: true, editing_program_id: nil)
     |> assign(program_form: to_form(ProgramCatalog.new_program_changeset()))
     |> assign(enrollment_form: to_form(Enrollment.new_policy_changeset(), as: "enrollment_policy"))
     |> assign(
       participant_policy_form: to_form(Enrollment.new_participant_policy_changeset(), as: "participant_policy")
     )
     |> assign(instructor_options: build_instructor_options(socket.assigns.current_scope.provider.id))
     |> push_patch(to: ~p"/provider/dashboard/programs")}
  end

  @impl true
  def handle_event("edit_program", %{"id" => program_id}, socket) do
    case ProgramCatalog.get_program_by_id(program_id) do
      {:ok, program} ->
        # Trigger: pre-populate the form with existing program data
        # Why: reuse the same program_form component for both create and edit
        # Outcome: form opens with current values, submit handler checks editing_program_id
        changeset = ProgramCatalog.new_program_changeset(program_to_form_params(program))

        {:noreply,
         socket
         |> assign(
           show_program_form: true,
           editing_program_id: program_id,
           program_form: to_form(changeset),
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

    # Trigger: program_id comes from client params (untrusted)
    # Why: without ownership check, any provider could view another's roster (IDOR)
    # Outcome: verify program belongs to logged-in provider before loading data
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
         can_message?: Entitlements.can_initiate_messaging?(socket.assigns.current_scope),
         invite_mode: "single",
         single_invite_form: blank_single_invite_form()
       )}
    else
      false ->
        Logger.warning("[DashboardLive] Unauthorized roster access attempt",
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

  # Trigger: "View sessions" action button on a row in the programs table
  # Why: program_id comes from client params (untrusted) — list_by_program is
  #      scoped to the provider_id from the server-side scope, so cross-provider
  #      peeking is impossible even if the client spoofs the id. The modal's
  #      title is derived from the authoritative projection result (not client
  #      params) to avoid displaying a spoofed title.
  # Outcome: modal opens with the program's sessions (empty list is valid);
  #          title falls back to a generic label when the program has zero sessions.
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

    # Trigger: parent_user_id comes from client — could be tampered
    # Why: validate against server-side roster to prevent messaging unauthorized parents
    # Outcome: rejects requests for non-roster or unconfirmed enrollments
    valid_confirmed? =
      Enum.any?(roster_entries, fn entry ->
        entry.parent_user_id == parent_user_id and entry.status == :confirmed
      end)

    if valid_confirmed? do
      case Messaging.create_direct_conversation(scope, provider_id, parent_user_id) do
        {:ok, conversation} ->
          {:noreply, push_navigate(socket, to: ~p"/provider/messages/#{conversation.id}")}

        {:error, :not_entitled} ->
          {:noreply, put_flash(socket, :error, gettext("Upgrade your plan to send messages."))}

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
        Logger.warning("[DashboardLive] Resend invite failed unexpectedly",
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

      {:error, reason} ->
        Logger.warning("[DashboardLive] Delete invite failed unexpectedly",
          invite_id: invite_id,
          reason: inspect(reason)
        )

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

    # Trigger: consume_uploaded_entries returns a list — may be empty if upload was cancelled
    # Why: consume_uploaded_entries unwraps the outer {:ok, _} from the callback,
    #      so we wrap File.read/1's result to preserve the inner {:ok, binary}/{:error, reason}
    # Outcome: empty list or I/O failure produces user-facing flash error
    # sobelow_skip ["Traversal.FileModule"]
    case safe_consume_uploaded_entries(socket, :csv_file, fn %{path: path}, _entry ->
           {:ok, File.read(path)}
         end) do
      {:error, :upload_channel_died} ->
        {:noreply, put_flash(socket, :error, gettext("Upload connection lost. Please try again."))}

      {:ok, []} ->
        {:noreply, put_flash(socket, :error, gettext("No file selected."))}

      {:ok, [{:error, reason}]} ->
        Logger.warning("[DashboardLive] CSV file read failed: #{inspect(reason)}")
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

            # Trigger: partial success — both `count` (imported) and `length(failed)` vary independently.
            # Why: composing two ngettext calls keeps each plural rule independent so translators
            #   can pluralise both halves correctly without combinatorial msgids.
            # Outcome: e.g. "Imported 1 family. 2 rows could not be processed."
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
     |> assign(program_form: to_form(changeset))
     |> assign(enrollment_form: to_form(enrollment_changeset, as: "enrollment_policy"))
     |> assign(participant_policy_form: to_form(participant_policy_changeset, as: "participant_policy"))}
  end

  @impl true
  def handle_event("save_program", %{"program_schema" => params} = all_params, socket) do
    provider = socket.assigns.current_scope.provider

    # Trigger: cover image upload may succeed, be absent, or fail
    # Why: upload failures warn but don't block program save
    # Outcome: all results flow through; cover_failed appends warning flash after save
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

    # Trigger: editing_program_id is nil for new programs, a UUID for edits
    # Why: reuse the same form and submit handler for both create and edit
    # Outcome: dispatch to create_new_program or update_existing_program
    case socket.assigns.editing_program_id do
      nil ->
        create_new_program(socket, attrs, all_params, cover_result)

      program_id ->
        update_existing_program(socket, program_id, attrs, all_params, cover_result)
    end
  end

  # ============================================================================
  # Dashboard Tab Events
  # ============================================================================

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

  # ============================================================================
  # Program Save Helpers
  # ============================================================================

  defp create_new_program(socket, attrs, all_params, cover_result) do
    program_params = all_params["program_schema"] || %{}
    enrollment_params = all_params["enrollment_policy"] || %{}
    participant_policy_params = all_params["participant_policy"] || %{}

    with {:ok, attrs} <- maybe_add_instructor(attrs, program_params["instructor_id"], socket),
         {:ok, program} <- ProgramCatalog.create_program(attrs, socket.assigns.current_scope.provider) do
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
       )
       |> update_program_slots(socket.assigns.business.program_slots_used + 1)}
    else
      {:error, :program_limit_reached} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("You've reached your program limit. Upgrade your plan to add more programs.")
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
         |> assign(program_form: to_form(Map.put(changeset, :action, :validate)))
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

      # Trigger: need enrollment data for the table view
      # Why: preserve existing enrollment count, update capacity from policy
      # Outcome: table row reflects updated program + current enrollment data
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
         |> assign(program_form: to_form(Map.put(changeset, :action, :validate)))
         |> put_flash(:error, gettext("Please fix the errors below."))}
    end
  end

  # ============================================================================
  # Staff Save Helpers
  # ============================================================================

  defp save_new_staff(socket, params, provider, headshot_result) do
    {headshot_status, attrs} =
      params
      |> atomize_staff_params()
      |> Map.put(:provider_id, provider.id)
      |> maybe_add_headshot(headshot_result)

    result = Provider.create_staff_member(attrs)

    # Extract staff member from either 2-tuple or 3-tuple success
    case result do
      {:ok, staff, _raw_token} ->
        handle_staff_created(socket, staff, headshot_status)

      {:ok, staff} ->
        handle_staff_created(socket, staff, headshot_status)

      {:error, {:validation_error, _errors}} ->
        changeset =
          params
          |> normalize_staff_form_params()
          |> Provider.new_staff_member_changeset()
          |> Map.put(:action, :validate)

        {:noreply,
         socket
         |> assign(staff_form: to_form(changeset))
         |> put_flash(:error, gettext("Please fix the errors below."))}

      {:error, :invitation_emission_failed} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Staff member created, but the invitation could not be sent. Try resending from the team list.")
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, staff_form: to_form(changeset))}
    end
  end

  defp handle_staff_created(socket, staff, headshot_status) do
    view = StaffMemberPresenter.to_admin_view(staff)

    flash_msg =
      if headshot_status == :headshot_failed,
        do: gettext("Team member added, but headshot upload failed."),
        else: gettext("Team member added.")

    {:noreply,
     socket
     |> stream_insert(:team_members, view)
     |> assign(show_staff_form: false)
     |> update_staff_count(socket.assigns.staff_count + 1)
     |> clear_flash(:error)
     |> put_flash(:info, flash_msg)}
  end

  defp save_existing_staff(socket, params, staff_id, headshot_result) do
    {headshot_status, attrs} =
      params
      |> atomize_staff_params()
      |> maybe_add_headshot(headshot_result)

    case Provider.update_staff_member(staff_id, attrs) do
      {:ok, staff} ->
        view = StaffMemberPresenter.to_admin_view(staff)

        flash_msg =
          if headshot_status == :headshot_failed,
            do: gettext("Team member updated, but headshot upload failed."),
            else: gettext("Team member updated.")

        {:noreply,
         socket
         |> stream_insert(:team_members, view)
         |> assign(show_staff_form: false)
         |> clear_flash(:error)
         |> put_flash(:info, flash_msg)}

      {:error, {:validation_error, _errors}} ->
        handle_staff_validation_error(socket, staff_id, params)

      {:error, changeset} ->
        {:noreply, assign(socket, staff_form: to_form(changeset))}
    end
  end

  defp handle_staff_validation_error(socket, staff_id, params) do
    case Provider.get_staff_member(staff_id) do
      {:ok, staff} ->
        changeset =
          Provider.change_staff_member(staff, normalize_staff_form_params(params))
          |> Map.put(:action, :validate)

        {:noreply,
         socket
         |> assign(staff_form: to_form(changeset))
         |> put_flash(:error, gettext("Please fix the errors below."))}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> assign(show_staff_form: false, editing_staff_id: nil)
         |> put_flash(:error, gettext("Staff member no longer exists."))}
    end
  end

  # ============================================================================
  # Render
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <%= case @live_action do %>
      <% :edit -> %>
        <div class={["min-h-screen", Theme.bg(:muted)]}>
          <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
            <.edit_profile_section
              form={@form}
              uploads={@uploads}
              business={@business}
              verification_docs={@streams.verification_docs}
              doc_type={@doc_type}
              document_types={@document_types}
            />
          </div>
        </div>
      <% _ -> %>
        <.pv_dashboard_chrome
          business={@business}
          can_create_program?={@can_create_program?}
          current_tab={dashboard_tab(@live_action)}
        >
          <.profile_completion_banner :if={@profile_draft?} />
          <.link
            :if={@dual_role?}
            id="cross-nav-staff-link"
            navigate={~p"/staff/dashboard"}
            class="inline-flex items-center gap-1 text-sm text-brand hover:text-brand/80"
          >
            {gettext("View your assignments")} →
          </.link>

          <%= case @live_action do %>
            <% :overview -> %>
              <.overview_section
                business={@business}
                total_sessions_completed={@total_sessions_completed}
                active_program_count={@programs_count}
                enrolled_total={@enrolled_total}
                pending_requests={@pending_requests}
                pending_enrollments={@pending_enrollments}
                top_programs={@top_programs}
              />
            <% :team -> %>
              <.team_section
                team_members={@streams.team_members}
                show_staff_form={@show_staff_form}
                editing_staff_id={@editing_staff_id}
                staff_form={@staff_form}
                uploads={@uploads}
                categories={@categories}
              />
            <% :programs -> %>
              <.programs_section
                programs={@streams.programs}
                staff_options={@staff_options}
                search_query={@search_query}
                selected_staff={@selected_staff}
                show_program_form={@show_program_form}
                program_form={@program_form}
                enrollment_form={@enrollment_form}
                participant_policy_form={@participant_policy_form}
                uploads={@uploads}
                instructor_options={@instructor_options}
                categories={@categories}
                editing_program_id={@editing_program_id}
                show_roster={@show_roster}
                roster_program_name={@roster_program_name}
                roster_program_id={@roster_program_id}
                roster_entries={@roster_entries}
                roster_tab={@roster_tab}
                roster_invites={@roster_invites}
                roster_enrolled_count={@roster_enrolled_count}
                roster_invite_count={@roster_invite_count}
                import_errors={@import_errors}
                can_message?={@can_message?}
                sessions_modal={@sessions_modal}
                invite_mode={@invite_mode}
                single_invite_form={@single_invite_form}
              />
          <% end %>
        </.pv_dashboard_chrome>
    <% end %>
    """
  end

  # Map this LV's live_action to the provider_nav_tabs vocabulary.
  # `:edit` falls back to :overview so the tab bar still shows a sensible
  # state when the edit screen is reached without going through a tab.
  defp dashboard_tab(:overview), do: :overview
  defp dashboard_tab(:team), do: :team
  defp dashboard_tab(:programs), do: :programs
  defp dashboard_tab(_), do: :overview

  # ============================================================================
  # Profile Completion Banner
  # ============================================================================

  defp profile_completion_banner(assigns) do
    ~H"""
    <div
      id="profile-completion-banner"
      class={[
        "mb-6 p-4 border-2 border-amber-300 bg-amber-50",
        Theme.rounded(:xl)
      ]}
    >
      <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
        <div class="flex items-start gap-3">
          <.icon name="hero-exclamation-triangle" class="w-6 h-6 text-amber-500 flex-shrink-0 mt-0.5" />
          <div>
            <h3 class={["font-semibold", Theme.typography(:card_title)]}>
              {gettext("Complete your provider profile")}
            </h3>
            <p class="text-sm text-gray-500 mt-0.5">
              {gettext(
                "Fill in your business details so parents can find you. Your profile will be reviewed by Klass Hero before going live."
              )}
            </p>
          </div>
        </div>
        <.link
          navigate={~p"/provider/complete-profile"}
          class={[
            "inline-flex items-center justify-center px-4 py-2 text-sm font-medium text-white whitespace-nowrap",
            Theme.rounded(:lg),
            Theme.gradient(:primary)
          ]}
        >
          {gettext("Complete Profile")}
        </.link>
      </div>
    </div>
    """
  end

  # ============================================================================
  # Edit Profile Template
  # ============================================================================

  defp edit_profile_section(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center gap-4 mb-6">
        <.link
          navigate={~p"/provider/dashboard"}
          class="flex items-center gap-1 text-hero-grey-500 hover:text-hero-charcoal transition-colors"
        >
          <.icon name="hero-arrow-left-mini" class="w-5 h-5" />
          {gettext("Back to Dashboard")}
        </.link>
      </div>

      <h1 class="text-2xl font-bold text-hero-charcoal">{gettext("Edit Profile")}</h1>

      <%!-- Profile Form --%>
      <div class={["bg-white p-6 shadow-sm border border-hero-grey-200", Theme.rounded(:xl)]}>
        <h2 class="text-lg font-semibold text-hero-charcoal mb-4">
          {gettext("Business Information")}
        </h2>

        <.form
          for={@form}
          id="profile-form"
          phx-change="validate_profile"
          phx-submit="save_profile"
          class="space-y-6"
        >
          <.input
            field={@form[:description]}
            type="textarea"
            label={gettext("Business Description")}
            placeholder={gettext("Tell parents about your organization...")}
            rows="4"
          />

          <%!-- Logo Upload --%>
          <div>
            <label class="block text-sm font-semibold text-hero-charcoal mb-2">
              {gettext("Business Logo")}
            </label>

            <div
              id="logo-upload"
              class={[
                "border-2 border-dashed border-hero-grey-300 p-6 text-center",
                Theme.rounded(:lg)
              ]}
              phx-drop-target={@uploads.logo.ref}
            >
              <%!-- Current logo preview --%>
              <div :if={@business.initials} class="mb-4">
                <div class={[
                  "w-16 h-16 mx-auto flex items-center justify-center text-white text-xl font-bold",
                  Theme.rounded(:full),
                  Theme.gradient(:primary)
                ]}>
                  {@business.initials}
                </div>
              </div>

              <%!-- Upload entries preview --%>
              <div :for={entry <- @uploads.logo.entries} class="mb-4">
                <.live_img_preview entry={entry} class="w-16 h-16 mx-auto rounded-full object-cover" />
                <p class="text-sm text-hero-grey-500 mt-1">{entry.client_name}</p>
                <button
                  type="button"
                  phx-click="cancel_upload"
                  phx-value-ref={entry.ref}
                  phx-value-upload="logo"
                  class="text-xs text-red-500 hover:text-red-700 mt-1"
                >
                  {gettext("Remove")}
                </button>
                <div
                  :for={err <- upload_errors(@uploads.logo, entry)}
                  class="text-xs text-red-500 mt-1"
                >
                  {upload_error_to_string(err)}
                </div>
              </div>

              <.live_file_input upload={@uploads.logo} class="hidden" />
              <label
                for={@uploads.logo.ref}
                class={[
                  "inline-flex items-center gap-2 px-4 py-2 border border-hero-grey-300",
                  "bg-white hover:bg-hero-grey-50 text-hero-charcoal text-sm font-medium cursor-pointer",
                  Theme.rounded(:lg),
                  Theme.transition(:normal)
                ]}
              >
                <.icon name="hero-photo-mini" class="w-4 h-4" />
                {gettext("Choose Logo")}
              </label>
              <p class="text-xs text-hero-grey-400 mt-2">
                {gettext("JPG, PNG or WebP. Max 2MB.")}
              </p>
            </div>
          </div>

          <div class="flex justify-end">
            <button
              type="submit"
              id="save-profile-btn"
              class={[
                "flex items-center gap-2 px-6 py-2.5 bg-hero-yellow hover:bg-hero-yellow-dark",
                "text-hero-charcoal font-semibold",
                Theme.rounded(:lg),
                Theme.transition(:normal)
              ]}
            >
              <.icon name="hero-check-mini" class="w-5 h-5" />
              {gettext("Save Changes")}
            </button>
          </div>
        </.form>
      </div>

      <.verification_documents_panel
        verification_docs={@verification_docs}
        uploads={@uploads}
        doc_type={@doc_type}
        document_types={@document_types}
      />
    </div>
    """
  end

  # ============================================================================
  # Dashboard Tab Templates
  # ============================================================================

  attr :business, :map, required: true
  attr :total_sessions_completed, :integer, required: true
  attr :active_program_count, :integer, required: true
  attr :enrolled_total, :integer, required: true
  attr :pending_requests, :list, required: true
  attr :pending_enrollments, :list, required: true
  attr :top_programs, :list, required: true

  defp overview_section(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- 4-up KPI grid. Revenue + Rating disabled until Stripe transactions
            and a review/rating model land. --%>
      <section id="provider-dashboard-stats" class="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <.pv_stat_card
          title={gettext("Active programs")}
          value={Integer.to_string(@active_program_count)}
          icon="hero-academic-cap"
          tone={:primary}
        />
        <.pv_stat_card
          title={gettext("Enrolled kids")}
          value={Integer.to_string(@enrolled_total)}
          icon="hero-users"
          tone={:cool}
          caption={gettext("Across all programs")}
        />
        <.pv_stat_card
          title={gettext("Revenue (this week)")}
          value="—"
          icon="hero-currency-euro"
          tone={:safety}
          disabled={true}
          caption={gettext("Coming soon")}
        />
        <.pv_stat_card
          title={gettext("Rating")}
          value="—"
          icon="hero-star"
          tone={:art}
          disabled={true}
          caption={gettext("Coming soon")}
        />
      </section>

      <%!-- Earnings chart placeholder — empty data renders the coming-soon explainer. --%>
      <section id="provider-earnings-chart">
        <.pv_earnings_chart data={[]} />
      </section>

      <%!-- Top programs + pending invites + pending enrollments side-by-side on desktop. --%>
      <section class="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <.kh_card class="p-5">
          <div class="flex items-center justify-between mb-4">
            <h3 class="font-bold text-lg">{gettext("Your top programs")}</h3>
            <.link
              navigate={~p"/provider/dashboard/programs"}
              class="text-sm font-bold text-[var(--brand-primary-dark)]"
            >
              {gettext("Manage")} →
            </.link>
          </div>
          <div :if={@top_programs == []} class="text-sm text-hero-grey-600">
            {gettext("No programs yet — add your first one from the Programs tab.")}
          </div>
          <div class="space-y-1">
            <.pv_program_row :for={p <- @top_programs} program={p} />
          </div>
        </.kh_card>

        <.kh_card class="p-5">
          <div class="flex items-center justify-between mb-4">
            <h3 class="font-bold text-lg">{gettext("Pending booking requests")}</h3>
            <span class="text-xs text-hero-grey-600 font-semibold">
              {length(@pending_requests)} {gettext("pending")}
            </span>
          </div>
          <div :if={@pending_requests == []} class="text-sm text-hero-grey-600">
            {gettext("No pending requests right now.")}
          </div>
          <div class="space-y-3">
            <.pv_request_card :for={r <- @pending_requests} request={r} />
          </div>
        </.kh_card>

        <.kh_card id="pending-enrollments-card" class="p-5">
          <div class="flex items-center justify-between mb-4">
            <h3 class="font-bold text-lg">{gettext("Pending enrollments")}</h3>
            <span class="text-xs text-hero-grey-600 font-semibold">
              {length(@pending_enrollments)} {gettext("pending")}
            </span>
          </div>
          <div :if={@pending_enrollments == []} class="text-sm text-hero-grey-600">
            {gettext("No pending enrollments right now.")}
          </div>
          <div class="space-y-3">
            <.pv_pending_enrollment_card
              :for={entry <- @pending_enrollments}
              entry={entry}
            />
          </div>
        </.kh_card>
      </section>

      <.business_profile_card business={@business} />

      <%!-- Subscription CTA — shows current plan and links to management page --%>
      <div
        id="subscription-cta"
        class="mt-4 rounded-lg border border-hero-blue-200 bg-hero-blue-50 p-4"
      >
        <div class="flex items-center justify-between">
          <div>
            <p class="text-sm font-medium text-zinc-900">
              {gettext("Current Plan: %{plan}", plan: @business.plan_label)}
            </p>
            <p :if={@business.plan == :starter} class="text-sm text-zinc-600 mt-0.5">
              {gettext("Upgrade your plan to unlock more features")}
            </p>
          </div>
          <.link
            navigate={~p"/provider/subscription"}
            class="text-sm font-medium text-hero-blue-600 hover:text-hero-blue-700 whitespace-nowrap"
          >
            {gettext("Manage Plan →")}
          </.link>
        </div>
      </div>
    </div>
    """
  end

  defp team_section(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h2 class="text-xl font-semibold text-hero-charcoal">
            {gettext("Team & Provider Profiles")}
          </h2>
          <p class="text-sm text-hero-grey-500">
            {gettext(
              "Create profiles for your staff. These will be visible to parents when assigned to programs."
            )}
          </p>
        </div>
        <.kh_button
          id="add-member-btn"
          variant={:yellow}
          size={:sm}
          icon="hero-user-plus-mini"
          phx-click="add_member"
        >
          {gettext("Add Team Member")}
        </.kh_button>
      </div>

      <%= if @show_staff_form do %>
        <.staff_member_form
          form={@staff_form}
          editing={@editing_staff_id != nil}
          uploads={@uploads}
          categories={@categories}
        />
      <% end %>

      <div
        id="team-members"
        phx-update="stream"
        class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6"
      >
        <div id="team-members-empty" class="hidden only:block col-span-full">
          <.empty_state
            icon="hero-user-group"
            title={gettext("No team members yet")}
            description={gettext("Add your first staff member to get started!")}
          />
        </div>
        <div :for={{id, member} <- @team_members} id={id}>
          <.team_member_card member={member} rate_label={member.rate_label} />
        </div>
      </div>
    </div>
    """
  end

  attr :programs, :any, required: true
  attr :staff_options, :list, required: true
  attr :search_query, :string, required: true
  attr :selected_staff, :string, required: true
  attr :show_program_form, :boolean, required: true
  attr :program_form, :any, required: true
  attr :enrollment_form, :any, required: true
  attr :participant_policy_form, :any, required: true
  attr :uploads, :map, required: true
  attr :instructor_options, :list, required: true
  attr :categories, :list, required: true
  attr :editing_program_id, :string, default: nil
  attr :show_roster, :boolean, required: true
  attr :roster_program_name, :string, default: nil
  attr :roster_program_id, :string, default: nil
  attr :roster_entries, :list, default: []
  attr :roster_tab, :string, default: "enrolled"
  attr :roster_invites, :list, default: []
  attr :roster_enrolled_count, :integer, default: 0
  attr :roster_invite_count, :integer, default: 0
  attr :import_errors, :any, default: nil
  attr :can_message?, :boolean, default: false
  attr :sessions_modal, :any, default: nil
  attr :invite_mode, :string, default: "single"
  attr :single_invite_form, :any, default: nil

  defp programs_section(assigns) do
    ~H"""
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
        programs={@programs}
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
    """
  end

  # ============================================================================
  # Upload Helpers
  # ============================================================================

  # Trigger: consume_uploaded_entries calls GenServer.call on the upload channel PID
  # Why: if the WebSocket reconnects (tab sleep, network hiccup) the PID is dead
  #      and an :exit propagates before the user callback runs
  # Outcome: wraps the call so dead-channel crashes return a tagged error tuple
  defp safe_consume_uploaded_entries(socket, upload_name, callback) do
    {:ok, consume_uploaded_entries(socket, upload_name, callback)}
  catch
    :exit, reason ->
      Logger.warning("Upload channel process died during consume",
        upload: upload_name,
        reason: inspect(reason)
      )

      {:error, :upload_channel_died}
  end

  # Trigger: upload entries may be empty (user didn't pick a file)
  # Why: consume_uploaded_entries returns [] when no entries exist
  # Outcome: {:ok, url} on success, :no_upload if no file selected, :upload_error on failure
  defp consume_single_upload(socket, upload_name, storage_prefix, provider_id) do
    case safe_consume_uploaded_entries(socket, upload_name, fn %{path: path}, entry ->
           try do
             # sobelow_skip ["Traversal.FileModule"]
             file_binary = File.read!(path)
             safe_name = String.replace(entry.client_name, ~r/[^a-zA-Z0-9._-]/, "_")
             storage_path = "#{storage_prefix}/providers/#{provider_id}/#{safe_name}"

             Storage.upload(:public, storage_path, file_binary, content_type: entry.client_type)
           catch
             # Trigger: storage adapter raises (rescue) or process is dead (exit)
             # Why: ExAws.request can raise; dead GenServer causes :exit
             # Outcome: return error tuple so consume_uploaded_entries doesn't crash
             kind, reason ->
               Logger.error("File upload failed",
                 upload: upload_name,
                 provider_id: provider_id,
                 kind: kind,
                 error: inspect(reason)
               )

               {:error, :upload_exception}
           end
         end) do
      {:error, :upload_channel_died} -> :upload_error
      # Trigger: consume_uploaded_entries unwraps {:ok, value} tuples
      # Why: the callback returns {:ok, url}, but the list contains only the url string
      # Outcome: match on a single-element list with a string URL
      {:ok, [url]} when is_binary(url) -> {:ok, url}
      {:ok, []} -> :no_upload
      {:ok, _other} -> :upload_error
    end
  end

  defp upload_logo(socket, provider_id) do
    consume_single_upload(socket, :logo, "logos", provider_id)
  end

  # Trigger: roster_program_id can be nil after close_roster fires
  # Why: list_program_invites/1 guard requires binary — nil raises FunctionClauseError
  # Outcome: nil program_id returns :no_program; valid id refreshes assigns
  defp refresh_invites(_socket, nil), do: {:error, :no_program}

  defp refresh_invites(socket, program_id) when is_binary(program_id) do
    {:ok, invites} = Enrollment.list_program_invites(program_id)
    invite_count = Enrollment.count_program_invites(program_id)
    {:ok, assign(socket, roster_invites: invites, roster_invite_count: invite_count)}
  end

  # Trigger: caller doesn't need to distinguish success from no-program
  # Why: avoids nesting a case inside an already-deep handler
  # Outcome: returns the (possibly refreshed) socket unchanged on error
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
  defp load_pending_requests(program_ids) do
    palette = ["#FFEAC9", "#33CFFF", "#FFFF36", "#FFD896"]

    program_ids
    |> Enum.flat_map(&safe_list_invites/1)
    |> Enum.with_index()
    |> Enum.map(fn {invite, idx} ->
      %{
        id: invite.id,
        parent: invite.invitee_name || invite.invitee_email || "Unknown",
        program: invite.program_id,
        child: invite[:child_name] || "—",
        when: invite[:created_at] && Calendar.strftime(invite.created_at, "%b %d"),
        color: Enum.at(palette, rem(idx, length(palette)))
      }
    end)
    |> Enum.take(5)
  end

  defp safe_list_invites(program_id) do
    case Enrollment.list_program_invites(program_id) do
      {:ok, invites} -> Enum.filter(invites, &(&1.status == :pending))
      _ -> []
    end
  end

  # Top 5 provider programs sorted by active-enrollment count desc.
  # Source is the rich %ProgramListing{} already loaded in handle_params.
  defp build_top_programs(listings, enrollment_counts) do
    today = Date.utc_today()

    listings
    |> Enum.map(&build_program_row(&1, enrollment_counts, today))
    |> Enum.sort_by(& &1.booked, :desc)
    |> Enum.take(5)
  end

  defp build_program_row(%ProgramListing{} = p, enrollment_counts, today) do
    %{
      id: p.id,
      title: p.title,
      booked: Map.get(enrollment_counts, p.id, 0),
      status: derive_program_status(p, today),
      cover: p.cover_image_url && "url(#{p.cover_image_url})"
    }
  end

  # %ProgramListing{} carries no explicit status; derive a coarse pill from its
  # registration and run-window dates. :full is capacity-driven and out of scope
  # here — capacity isn't projected onto the listing read model.
  defp derive_program_status(%ProgramListing{} = p, today) do
    cond do
      not_yet_open?(p.registration_start_date, today) -> :draft
      past?(p.registration_end_date, today) -> :archived
      past?(p.end_date, today) -> :archived
      true -> :live
    end
  end

  defp not_yet_open?(nil, _today), do: false
  defp not_yet_open?(start_date, today), do: Date.before?(today, start_date)

  defp past?(nil, _today), do: false
  defp past?(date, today), do: Date.after?(today, date)

  defp fetch_verification_docs(provider_id) do
    case Provider.get_provider_verification_documents(provider_id) do
      {:ok, docs} ->
        docs

      {:error, reason} ->
        Logger.error("[DashboardLive] Failed to load verification documents",
          provider_id: provider_id,
          reason: inspect(reason)
        )

        []
    end
  end

  defp update_staff_count(socket, count) do
    business = %{socket.assigns.business | team_seats_used: count}
    assign(socket, staff_count: count, business: business)
  end

  defp update_program_slots(socket, count) do
    business = %{socket.assigns.business | program_slots_used: count}

    socket
    |> assign(business: business)
    |> update_can_create_program()
  end

  defp update_can_create_program(socket) do
    provider = socket.assigns.current_scope.provider
    used = socket.assigns.business.program_slots_used
    can_create? = Entitlements.can_create_program?(provider, used)
    assign(socket, can_create_program?: can_create?)
  end

  defp fetch_staff_members(provider_id) do
    case Provider.list_staff_members(provider_id) do
      {:ok, members} ->
        members

      {:error, reason} ->
        Logger.error("[DashboardLive] Failed to load staff members",
          provider_id: provider_id,
          reason: inspect(reason)
        )

        []
    end
  end

  defp refresh_staff_options(socket) do
    provider_id = socket.assigns.current_scope.provider.id
    staff_members = fetch_staff_members(provider_id)
    staff_views = StaffMemberPresenter.to_admin_view_list(staff_members)

    staff_options =
      [%{value: "all", label: gettext("All Staff")}] ++
        Enum.map(staff_views, &%{value: &1.id, label: &1.full_name})

    assign(socket, staff_options: staff_options)
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
    |> update_program_slots(ProgramCatalog.count_self_posted_programs(socket.assigns.current_scope.provider.id))
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

  defp upload_headshot(socket, provider_id) do
    consume_single_upload(socket, :headshot, "headshots", provider_id)
  end

  defp atomize_staff_params(params) do
    # Trigger: form params arrive as string keys with "" for unfilled optional fields
    # Why: use cases and domain model expect atom keys; empty strings must become nil
    #      for optional fields; hidden checkbox input sends [""] when unchecked
    # Outcome: clean map ready for domain validation
    %{
      first_name: params["first_name"],
      last_name: params["last_name"],
      role: presence(params["role"]),
      email: presence(params["email"]),
      bio: presence(params["bio"]),
      tags: (params["tags"] || []) |> Enum.reject(&(&1 == "")),
      qualifications: parse_qualifications(params["qualifications"]),
      pay_rate: build_pay_rate_from_params(params)
    }
  end

  defp build_pay_rate_from_params(%{"rate_type" => "hourly"} = params) do
    build_pay_rate(&PayRate.hourly/2, params)
  end

  defp build_pay_rate_from_params(%{"rate_type" => "per_session"} = params) do
    build_pay_rate(&PayRate.per_session/2, params)
  end

  defp build_pay_rate_from_params(_params), do: nil

  # When rate_type is present but construction fails (bad amount, unknown currency, etc.),
  # return the `:invalid` sentinel rather than `nil`. Domain validation via
  # `StaffMember.validate_pay_rate/2` rejects non-PayRate non-nil values, which surfaces
  # an `{:error, {:validation_error, _}}` tuple from the use case. The LiveView's
  # existing error branch then re-renders the form via the schema's changeset, which
  # flags bad `rate_amount` strings (Decimal cast failure) directly on the field.
  defp build_pay_rate(constructor, params) do
    amount = presence(params["rate_amount"])
    currency = presence(params["rate_currency"]) || "EUR"

    case amount && constructor.(amount, currency) do
      {:ok, pay_rate} -> pay_rate
      _ -> :invalid
    end
  end

  defp presence(""), do: nil
  defp presence(nil), do: nil
  defp presence(value), do: value

  defp parse_decimal(nil), do: nil
  defp parse_decimal(""), do: nil
  defp parse_decimal(%Decimal{} = d), do: d

  defp parse_decimal(value) when is_binary(value) do
    # Trigger: user typed a non-numeric string in the price field
    # Why: Decimal.new/1 raises on invalid input — must use parse/1 to avoid crash
    # Outcome: nil lets downstream domain validation catch "price is required"
    value
    |> String.trim()
    |> Decimal.parse()
    |> case do
      {decimal, ""} -> decimal
      _other -> nil
    end
  end

  defp parse_meeting_days(nil), do: []
  defp parse_meeting_days(days) when is_list(days), do: Enum.reject(days, &(&1 == ""))
  defp parse_meeting_days(_), do: []

  defp parse_time(nil), do: nil
  defp parse_time(""), do: nil

  defp parse_time(value) when is_binary(value) do
    # Try parsing as-is first (handles "HH:MM:SS" from re-rendered %Time{} structs),
    # then fall back to appending ":00" (handles "HH:MM" from HTML time inputs)
    case Time.from_iso8601(value) do
      {:ok, time} ->
        time

      {:error, _} ->
        case Time.from_iso8601(value <> ":00") do
          {:ok, time} -> time
          {:error, _} -> nil
        end
    end
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  defp parse_qualifications(nil), do: []
  defp parse_qualifications(""), do: []

  defp parse_qualifications(quals) when is_binary(quals) do
    quals
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_qualifications(quals) when is_list(quals), do: quals

  # Trigger: validate_staff sends raw form params with qualifications as a comma-separated string
  # Why: Ecto's cast rejects a plain string for {:array, :string} — must pre-parse before changeset
  # Outcome: changeset receives a list, matching what atomize_staff_params does on the save path
  defp normalize_staff_form_params(params) do
    Map.put(params, "qualifications", parse_qualifications(params["qualifications"]))
  end

  defp maybe_add_headshot(attrs, {:ok, url}), do: {:ok, Map.put(attrs, :headshot_url, url)}
  defp maybe_add_headshot(attrs, :no_upload), do: {:ok, attrs}
  defp maybe_add_headshot(attrs, :upload_error), do: {:headshot_failed, attrs}

  defp upload_program_cover(socket, provider_id) do
    consume_single_upload(socket, :program_cover, "program_covers", provider_id)
  end

  defp maybe_add_cover_image(attrs, {:ok, url}), do: Map.put(attrs, :cover_image_url, url)
  defp maybe_add_cover_image(attrs, :no_upload), do: attrs

  defp maybe_add_cover_image(attrs, :upload_error), do: attrs

  # Trigger: cover upload failed but program saved successfully
  # Why: non-blocking UX — warn about upload failure without losing the program save
  # Outcome: warning flash appended so user knows to retry the cover image
  defp maybe_flash_cover_warning(socket, :upload_error) do
    put_flash(
      socket,
      :warning,
      gettext("Program saved, but the cover image upload failed. You can re-upload it by editing the program.")
    )
  end

  defp maybe_flash_cover_warning(socket, _cover_result), do: socket

  # Trigger: instructor_id may be nil/"" (none selected) or a valid UUID
  # Why: instructor is optional; when selected, we resolve display data from Provider
  # Outcome: {:ok, attrs} enriched with instructor data, or {:error, :instructor_not_found}
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
    case Provider.list_active_staff_members(provider_id) do
      {:ok, members} ->
        staff_to_options(members)

      {:error, reason} ->
        Logger.error("Failed to load instructor options",
          provider_id: provider_id,
          reason: inspect(reason)
        )

        []
    end
  end

  defp staff_to_options(members) do
    Enum.map(members, fn m -> {Provider.staff_member_full_name(m), m.id} end)
  end

  # Trigger: both capacity fields are blank
  # Why: no policy needed when provider doesn't set capacity constraints
  # Outcome: skip policy creation, return :ok
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

        # Trigger: policy save failed (e.g. min > max validation)
        # Why: program already created — don't roll back, but warn provider
        # Outcome: propagate error so with chain shows a warning flash
        {:error, reason} ->
          Logger.warning("[Provider.DashboardLive] Failed to save enrollment policy",
            program_id: program_id,
            reason: inspect(reason)
          )

          {:error, :enrollment_policy_failed}
      end
    end
  end

  # Trigger: program just created and has no policy row yet
  # Why: avoid persisting an all-nil policy when the provider set no restrictions
  # Outcome: skip the upsert entirely if every restriction field is empty
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
      # Trigger: hidden input for checkbox group sends [""] when none checked
      # Why: must filter empty strings to detect truly empty gender selection
      # Outcome: clean list of selected gender values
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

  # Trigger: eligibility_at parsed as nil — only reachable via malformed callers;
  #   the LiveView form always submits one of the radio values
  # Why: forwarding `nil` would violate the column's NOT NULL + check constraint;
  #   the repo's on_conflict {:replace, [:eligibility_at, ...]} would *not* preserve
  #   any stored value either, so we don't pretend to.
  # Outcome: drop the key so the INSERT falls back to the schema default
  #   ("registration"); on conflict that default still replaces any stored value,
  #   which is acceptable because the form makes nil unreachable in practice.
  defp drop_nil_eligibility_at(%{eligibility_at: nil} = attrs), do: Map.delete(attrs, :eligibility_at)

  defp drop_nil_eligibility_at(attrs), do: attrs

  defp save_participant_policy(attrs, program_id) do
    case Enrollment.set_participant_policy(attrs) do
      {:ok, _policy} ->
        :ok

      {:error, reason} ->
        Logger.warning("[Provider.DashboardLive] Failed to save participant policy",
          program_id: program_id,
          reason: inspect(reason)
        )

        {:error, :participant_policy_failed}
    end
  end

  # Trigger: program created, but enrollment policy may have failed
  # Why: program is already persisted — don't roll back, just adjust flash
  # Outcome: success flash if policy ok, warning flash if policy failed
  defp resolve_capacity(:ok, enrollment_params), do: parse_integer(enrollment_params["max_enrollment"])

  defp resolve_capacity({:error, _}, _enrollment_params), do: nil

  # Trigger: program created, but enrollment policy may have failed
  # Why: program is already persisted — don't roll back, just adjust flash
  # Outcome: success flash if policy ok, warning flash if policy failed
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

  defp parse_integer(nil), do: nil
  defp parse_integer(""), do: nil

  defp parse_integer(val) when is_binary(val) do
    case Integer.parse(val) do
      {int, ""} when int >= 1 -> int
      _ -> nil
    end
  end

  defp parse_integer(val) when is_integer(val), do: val

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

  defp nil_safe(nil, _fun), do: nil
  defp nil_safe(value, fun), do: fun.(value)

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

  defp refresh_pending_enrollments(socket) do
    provider = socket.assigns.current_scope.provider
    program_ids = ProgramCatalog.list_programs_for_provider(provider.id) |> Enum.map(& &1.id)
    assign(socket, :pending_enrollments, Enrollment.list_pending_enrollments_for_provider(program_ids))
  end
end
