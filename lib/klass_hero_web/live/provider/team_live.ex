defmodule KlassHeroWeb.Provider.TeamLive do
  @moduledoc """
  Provider team management: staff member profiles, self-staffing, headshot uploads,
  and invitation resends.

  Split out of the former `DashboardLive` god-module (#904). Owns the
  `team_members` stream and the staff form; renders inside the shared
  `pv_dashboard_shell`.
  """
  use KlassHeroWeb, :live_view

  import KlassHeroWeb.ProviderComponents

  alias KlassHero.Accounts
  alias KlassHero.ProgramCatalog
  alias KlassHero.Provider
  alias KlassHero.Shared.NameUtils
  alias KlassHeroWeb.Presenters.StaffMemberPresenter
  alias KlassHeroWeb.Provider.Dashboard.Chrome
  alias KlassHeroWeb.Provider.Dashboard.Params
  alias KlassHeroWeb.Provider.Dashboard.Uploads

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    provider = socket.assigns.current_scope.provider
    scope = socket.assigns.current_scope

    staff_members = fetch_staff_members(provider.id)
    {current_views, former_views} = roster_views(staff_members, provider.id)

    socket =
      socket
      |> Chrome.assign()
      |> assign(page_title: gettext("Team & Profiles"))
      |> assign(active_nav: :home)
      |> assign(:self_staffed?, self_staffed?(staff_members, scope))
      |> assign(:self_staffing?, false)
      |> stream(:team_members, current_views)
      |> stream(:former_members, former_views)
      |> update_staff_count(length(current_views))
      |> assign(former_count: length(former_views))
      |> assign(show_staff_form: false, editing_staff_id: nil)
      |> assign(staff_form: to_form(Provider.new_staff_member_changeset(), as: :staff_member_schema))
      |> assign(categories: ProgramCatalog.program_categories())
      |> allow_upload(:headshot,
        accept: ~w(.jpg .jpeg .png .webp),
        max_entries: 1,
        max_file_size: 1_000_000
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("add_member", _params, socket) do
    {:noreply,
     socket
     |> assign(show_staff_form: true, editing_staff_id: nil, self_staffing?: false)
     |> assign(staff_form: to_form(Provider.new_staff_member_changeset(), as: :staff_member_schema))}
  end

  @impl true
  def handle_event("add_self", _params, socket) do
    user = socket.assigns.current_scope.user
    {first_name, last_name} = NameUtils.split_first_last(user.name)

    prefill = %{
      "first_name" => first_name,
      "last_name" => last_name,
      "email" => user.email
    }

    {:noreply,
     socket
     |> assign(show_staff_form: true, editing_staff_id: nil, self_staffing?: true)
     |> assign(staff_form: to_form(Provider.new_staff_member_changeset(prefill), as: :staff_member_schema))}
  end

  @impl true
  def handle_event("edit_member", %{"id" => staff_id}, socket) do
    provider_id = socket.assigns.current_scope.provider.id

    # staff_id is untrusted client input; the scoped getter makes a foreign row
    # unreachable (IDOR guard) rather than fetched and then compared.
    case Provider.get_staff_member(staff_id, provider_id) do
      {:ok, staff} ->
        changeset = Provider.change_staff_member(staff)

        {:noreply,
         socket
         |> assign(show_staff_form: true, editing_staff_id: staff_id, self_staffing?: false)
         |> assign(staff_form: to_form(changeset, as: :staff_member_schema))}

      {:error, :not_found} ->
        # Logged either way so enumeration is visible; the user sees one message.
        Logger.warning("[TeamLive] Staff edit attempt for unknown or foreign member",
          staff_member_id: staff_id,
          provider_id: provider_id
        )

        {:noreply, put_flash(socket, :error, gettext("Staff member not found."))}
    end
  end

  @impl true
  def handle_event("close_staff_form", _params, socket) do
    {:noreply, assign(socket, show_staff_form: false, self_staffing?: false)}
  end

  @impl true
  def handle_event("validate_staff", %{"staff_member_schema" => params}, socket) do
    params = normalize_staff_form_params(params)
    provider_id = socket.assigns.current_scope.provider.id

    changeset =
      case socket.assigns.editing_staff_id do
        nil ->
          Provider.new_staff_member_changeset(params)

        staff_id ->
          # Member may have been deleted between form open and keystroke — fall back
          # to a new changeset. Ownership is re-checked here too (defence in depth):
          # a foreign row must never rehydrate into the form via a crafted event.
          case Provider.get_staff_member(staff_id, provider_id) do
            {:ok, staff} ->
              Provider.change_staff_member(staff, params)

            _not_found_or_foreign ->
              Provider.new_staff_member_changeset(params)
          end
      end

    {:noreply, assign(socket, staff_form: to_form(Map.put(changeset, :action, :validate), as: :staff_member_schema))}
  end

  @impl true
  def handle_event("save_staff", %{"staff_member_schema" => params}, socket) do
    provider = socket.assigns.current_scope.provider

    headshot_result = upload_headshot(socket, provider.id)

    case {socket.assigns.editing_staff_id, socket.assigns.self_staffing?} do
      {nil, true} -> save_self_staff(socket, params, headshot_result)
      {nil, false} -> save_new_staff(socket, params, provider, headshot_result)
      {staff_id, _} -> save_existing_staff(socket, params, staff_id, headshot_result)
    end
  end

  @impl true
  def handle_event("end_employment", %{"id" => staff_id}, socket) do
    provider_id = socket.assigns.current_scope.provider.id

    # Accounts orchestrates: Provider offboards (every program assignment retired,
    # which is what takes them out of the programs' conversations — #1292) and
    # Accounts durably drops :staff when no other active employment remains (#972),
    # atomically. It also enforces provider ownership — a foreign staff_id comes
    # back as :not_found.
    case Accounts.offboard_staff_member(provider_id, staff_id) do
      {:ok, offboarded} ->
        {:noreply,
         socket
         |> move_to_former(offboarded)
         |> heal_after_self_delete({:ok, offboarded})
         |> clear_flash(:error)
         |> put_flash(:info, gettext("Team member removed from the team."))}

      {:error, :not_found} ->
        {:noreply, staff_not_found(socket, "offboard", staff_id, provider_id)}
    end
  end

  @impl true
  def handle_event("reactivate_member", %{"id" => staff_id}, socket) do
    provider_id = socket.assigns.current_scope.provider.id

    with {:ok, staff} <- Provider.get_staff_member(staff_id, provider_id),
         {:ok, reactivated} <- Provider.reactivate_staff_member(staff) do
      {:noreply,
       socket
       |> move_to_current(reactivated)
       |> heal_after_self_reactivate(reactivated)
       |> clear_flash(:error)
       # Employment only: assignments retired on offboarding do not come back,
       # so say so rather than let "reactivated" imply their programs returned.
       |> put_flash(:info, gettext("Team member is back. Assign them to programs again when you're ready."))}
    else
      {:error, :not_found} ->
        {:noreply, staff_not_found(socket, "reactivate", staff_id, provider_id)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not bring this team member back. Please try again."))}
    end
  end

  @impl true
  def handle_event("delete_member", %{"id" => staff_id}, socket) do
    provider_id = socket.assigns.current_scope.provider.id

    case Accounts.remove_staff_member(provider_id, staff_id) do
      {:ok, deleted} ->
        {:noreply,
         socket
         |> stream_delete_by_dom_id(:team_members, "team_members-#{staff_id}")
         |> update_staff_count(max(0, socket.assigns.staff_count - 1))
         |> heal_after_self_delete({:ok, deleted})
         |> clear_flash(:error)
         |> put_flash(:info, gettext("Team member removed."))}

      # The card only offers Delete on a row with no history, so this is a stale
      # tab: someone was invited or assigned since the page loaded.
      {:error, :has_history} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("This person has a history here now — use 'Remove from team' instead.")
         )}

      {:error, :not_found} ->
        {:noreply, staff_not_found(socket, "delete", staff_id, provider_id)}
    end
  end

  @impl true
  def handle_event("resend_invitation", %{"id" => staff_member_id}, socket) do
    provider_id = socket.assigns.current_scope.provider.id

    case Provider.resend_staff_invitation(provider_id, staff_member_id) do
      {:ok, updated, _raw_token} ->
        staff_view = StaffMemberPresenter.to_admin_view(updated)

        {:noreply,
         socket
         |> stream_insert(:team_members, staff_view)
         |> put_flash(:info, gettext("Invitation resent successfully."))}

      {:error, :not_found} ->
        # Log the attempt so enumeration is visible.
        Logger.warning("[TeamLive] Resend invitation returned not_found",
          staff_member_id: staff_member_id,
          provider_id: provider_id
        )

        {:noreply, put_flash(socket, :error, gettext("Staff member not found."))}

      {:error, :invalid_invitation_transition} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("This invitation cannot be resent in its current state.")
         )}

      {:error, reason} ->
        Logger.warning("[TeamLive] Resend invitation failed",
          staff_member_id: staff_member_id,
          reason: inspect(reason)
        )

        {:noreply, put_flash(socket, :error, gettext("Failed to resend invitation. Please try again."))}
    end
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref, "upload" => upload_name}, socket) do
    {:noreply, cancel_upload(socket, String.to_existing_atom(upload_name), ref)}
  end

  # The shared dashboard header's "New Program" CTA lives on every tab; from Team
  # it navigates to the Programs tab with the create form opened.
  @impl true
  def handle_event("add_program", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/provider/dashboard/programs?new=1")}
  end

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
         |> assign(staff_form: to_form(changeset, as: :staff_member_schema))
         |> put_flash(:error, gettext("Please fix the errors below."))}

      {:error, changeset} ->
        {:noreply, assign(socket, staff_form: to_form(changeset, as: :staff_member_schema))}
    end
  end

  defp save_self_staff(socket, params, headshot_result) do
    {headshot_status, attrs} =
      params
      |> atomize_staff_params()
      |> maybe_add_headshot(headshot_result)

    case Accounts.add_self_as_staff(socket.assigns.current_scope.user, attrs) do
      {:ok, _user, staff} ->
        handle_self_staffed(socket, staff, headshot_status)

      {:error, :already_staffed} ->
        # Stale tab: they self-staffed elsewhere. The row exists but isn't in
        # this tab's memory, so converge the whole page: flags, nav, roster.
        provider_id = socket.assigns.current_scope.provider.id
        {current_views, former_views} = roster_views(fetch_staff_members(provider_id), provider_id)

        {:noreply,
         socket
         |> stream(:team_members, current_views, reset: true)
         |> stream(:former_members, former_views, reset: true)
         |> update_staff_count(length(current_views))
         |> assign(former_count: length(former_views))
         |> assign(show_staff_form: false, self_staffing?: false)
         |> assign(self_staffed?: true, dual_role?: true)
         |> put_flash(:info, gettext("You're already on your team."))}

      {:error, {:validation_error, _errors}} ->
        changeset =
          params
          |> normalize_staff_form_params()
          |> Provider.new_staff_member_changeset()
          |> Map.put(:action, :validate)

        {:noreply,
         socket
         |> assign(staff_form: to_form(changeset, as: :staff_member_schema))
         |> put_flash(:error, gettext("Please fix the errors below."))}

      {:error, reason} ->
        Logger.error("Failed to self-staff provider",
          user_id: socket.assigns.current_scope.user.id,
          reason: inspect(reason)
        )

        {:noreply, put_flash(socket, :error, gettext("Could not add you to the team. Please try again."))}
    end
  end

  defp self_staffed?(staff_members, scope) do
    Enum.any?(staff_members, &(&1.user_id == scope.user.id and &1.active))
  end

  # The provider just deleted their OWN staff row: the self-staff CTA must
  # come back, and the staff-dashboard cross-nav only stays if they're still
  # active staff somewhere else (multi-employer).
  defp heal_after_self_delete(socket, {:ok, %{user_id: user_id}}) do
    if user_id == socket.assigns.current_scope.user.id do
      still_staff_somewhere? =
        match?({:ok, _}, Provider.get_active_staff_member_by_user(user_id))

      assign(socket, self_staffed?: false, dual_role?: still_staff_somewhere?)
    else
      socket
    end
  end

  defp heal_after_self_delete(socket, _not_found), do: socket

  defp handle_self_staffed(socket, staff, headshot_status) do
    flash_msg =
      if headshot_status == :headshot_failed,
        do: gettext("You're on the team, but the headshot upload failed."),
        else: gettext("You're on the team — you can now be assigned to programs.")

    {:noreply,
     socket
     |> stream_insert(:team_members, StaffMemberPresenter.to_admin_view(staff))
     |> update_staff_count(socket.assigns.staff_count + 1)
     |> assign(show_staff_form: false, self_staffing?: false)
     |> assign(self_staffed?: true, dual_role?: true)
     |> clear_flash(:error)
     |> put_flash(:info, flash_msg)}
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
    provider_id = socket.assigns.current_scope.provider.id

    {headshot_status, attrs} =
      params
      |> atomize_staff_params()
      |> maybe_add_headshot(headshot_result)

    case Provider.update_staff_member(provider_id, staff_id, attrs) do
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

      # Ownership mismatch or a row deleted mid-edit both surface as :not_found —
      # an atom, not a changeset, so it must not fall through to the clause below
      # (to_form(:not_found, ...) would raise). Mirrors handle_staff_validation_error.
      {:error, :not_found} ->
        {:noreply,
         socket
         |> assign(show_staff_form: false, editing_staff_id: nil)
         |> put_flash(:error, gettext("Staff member no longer exists."))}

      {:error, changeset} ->
        {:noreply, assign(socket, staff_form: to_form(changeset, as: :staff_member_schema))}
    end
  end

  defp handle_staff_validation_error(socket, staff_id, params) do
    provider_id = socket.assigns.current_scope.provider.id

    # Ownership re-checked (defence in depth): a foreign row is treated as gone.
    case Provider.get_staff_member(staff_id, provider_id) do
      {:ok, staff} ->
        changeset =
          Provider.change_staff_member(staff, normalize_staff_form_params(params))
          |> Map.put(:action, :validate)

        {:noreply,
         socket
         |> assign(staff_form: to_form(changeset, as: :staff_member_schema))
         |> put_flash(:error, gettext("Please fix the errors below."))}

      _not_found_or_foreign ->
        {:noreply,
         socket
         |> assign(show_staff_form: false, editing_staff_id: nil)
         |> put_flash(:error, gettext("Staff member no longer exists."))}
    end
  end

  defp update_staff_count(socket, count) do
    assign(socket, staff_count: count)
  end

  # Log the attempt so an enumeration attack is visible.
  defp staff_not_found(socket, action, staff_id, provider_id) do
    Logger.warning("[TeamLive] Staff #{action} returned not_found",
      staff_member_id: staff_id,
      provider_id: provider_id
    )

    put_flash(socket, :error, gettext("Staff member not found."))
  end

  defp fetch_staff_members(provider_id) do
    {:ok, members} = Provider.list_staff_members(provider_id)
    members
  end

  # The roster read is not active-filtered, so the tab splits it: people who work
  # here, and former team members kept for their history (and for Reactivate).
  # `staff_count` counts the current team only.
  defp roster_views(staff_members, provider_id) do
    erasable = Provider.erasable_staff_ids(provider_id)
    {current, former} = Enum.split_with(staff_members, & &1.active)

    {StaffMemberPresenter.to_admin_view_list(current, erasable),
     StaffMemberPresenter.to_admin_view_list(former, erasable)}
  end

  defp move_to_former(socket, staff) do
    socket
    |> stream_delete_by_dom_id(:team_members, "team_members-#{staff.id}")
    |> stream_insert(:former_members, StaffMemberPresenter.to_admin_view(staff))
    |> update_staff_count(max(0, socket.assigns.staff_count - 1))
    |> assign(former_count: socket.assigns.former_count + 1)
  end

  defp move_to_current(socket, staff) do
    erasable = Provider.erasable_staff_ids(staff.provider_id)

    socket
    |> stream_delete_by_dom_id(:former_members, "former_members-#{staff.id}")
    |> stream_insert(:team_members, StaffMemberPresenter.to_admin_view(staff, erasable))
    |> update_staff_count(socket.assigns.staff_count + 1)
    |> assign(former_count: max(0, socket.assigns.former_count - 1))
  end

  # Mirror of heal_after_self_delete/2: reinstating their own row restores the
  # self-staff state and the staff-dashboard cross-nav.
  defp heal_after_self_reactivate(socket, %{user_id: user_id}) do
    if user_id == socket.assigns.current_scope.user.id do
      assign(socket, self_staffed?: true, dual_role?: true)
    else
      socket
    end
  end

  defp upload_headshot(socket, provider_id) do
    Uploads.consume_single_upload(socket, :headshot, "headshots", provider_id)
  end

  defp atomize_staff_params(params) do
    base = %{
      first_name: params["first_name"],
      last_name: params["last_name"],
      role: Params.presence(params["role"]),
      email: Params.presence(params["email"]),
      bio: Params.presence(params["bio"]),
      tags: (params["tags"] || []) |> Enum.reject(&(&1 == "")),
      qualifications: parse_qualifications(params["qualifications"])
    }

    Map.merge(base, flat_rate_params(params))
  end

  # Pass raw rate_* params straight to the Provider facade — StaffMember's changeset is
  # the pay-rate validation gatekeeper (#1060). The rate_currency field is a hidden EUR
  # input that is always submitted, so the three columns are gated on an actual rate_type
  # selection; otherwise a rate-less staff member would trip the all-or-none constraint.
  defp flat_rate_params(%{"rate_type" => type} = params) when type in ["hourly", "per_session"] do
    %{
      rate_type: type,
      rate_amount: Params.presence(params["rate_amount"]),
      rate_currency: Params.presence(params["rate_currency"]) || "EUR"
    }
  end

  defp flat_rate_params(_params), do: %{rate_type: nil, rate_amount: nil, rate_currency: nil}

  defp parse_qualifications(nil), do: []
  defp parse_qualifications(""), do: []

  defp parse_qualifications(quals) when is_binary(quals) do
    quals
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_qualifications(quals) when is_list(quals), do: quals

  # Ecto's {:array, :string} cast rejects a plain string; pre-parse to list before changeset.
  defp normalize_staff_form_params(params) do
    Map.put(params, "qualifications", parse_qualifications(params["qualifications"]))
  end

  defp maybe_add_headshot(attrs, {:ok, url}), do: {:ok, Map.put(attrs, :headshot_url, url)}
  defp maybe_add_headshot(attrs, :no_upload), do: {:ok, attrs}
  defp maybe_add_headshot(attrs, :upload_error), do: {:headshot_failed, attrs}

  @impl true
  def render(assigns) do
    ~H"""
    <.pv_dashboard_shell
      business={@business}
      current_tab={:team}
      profile_draft?={@profile_draft?}
      dual_role?={@dual_role?}
    >
      <div class="space-y-6">
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <div>
            <h2 class="text-xl font-semibold text-hero-black-100">
              {gettext("Team & Provider Profiles")}
            </h2>
            <p class="text-sm text-[var(--fg-muted)]">
              {gettext(
                "Create profiles for your staff. These will be visible to parents when assigned to programs."
              )}
            </p>
          </div>
          <div class="flex flex-col sm:flex-row gap-2">
            <.kh_button
              :if={not @self_staffed?}
              id="self-staff-btn"
              variant={:secondary}
              size={:sm}
              icon="hero-academic-cap-mini"
              phx-click="add_self"
            >
              {gettext("I'll be teaching")}
            </.kh_button>
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
        </div>

        <%= if @show_staff_form do %>
          <.staff_member_form
            form={@staff_form}
            editing={@editing_staff_id != nil}
            uploads={@uploads}
            categories={@categories}
            email_readonly={@self_staffing?}
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
          <div :for={{id, member} <- @streams.team_members} id={id}>
            <.team_member_card member={member} rate_label={member.rate_label} />
          </div>
        </div>

        <%!-- Streams cannot report their own size, so the section is gated on a
              counted assign rather than on the stream (see LiveView streams). --%>
        <div :if={@former_count > 0} id="former-members-section" class="space-y-3">
          <h3 id="former-members-heading" class={KlassHeroWeb.Theme.typography(:card_title)}>
            {gettext("Former team members")}
          </h3>
          <div id="former-members" phx-update="stream" class="space-y-3">
            <div :for={{id, member} <- @streams.former_members} id={id}>
              <.former_member_card member={member} />
            </div>
          </div>
        </div>
      </div>
    </.pv_dashboard_shell>
    """
  end
end
