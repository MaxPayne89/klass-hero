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
  alias KlassHero.Provider.PayRate
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
    staff_views = StaffMemberPresenter.to_admin_view_list(staff_members)

    socket =
      socket
      |> Chrome.assign()
      |> assign(page_title: gettext("Team & Profiles"))
      |> assign(:self_staffed?, self_staffed?(staff_members, scope))
      |> assign(:self_staffing?, false)
      |> stream(:team_members, staff_views)
      |> update_staff_count(length(staff_views))
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
    case Provider.get_staff_member(staff_id) do
      {:ok, staff} ->
        changeset = Provider.change_staff_member(staff)

        {:noreply,
         socket
         |> assign(show_staff_form: true, editing_staff_id: staff_id, self_staffing?: false)
         |> assign(staff_form: to_form(changeset, as: :staff_member_schema))}

      {:error, :not_found} ->
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

    changeset =
      case socket.assigns.editing_staff_id do
        nil ->
          Provider.new_staff_member_changeset(params)

        staff_id ->
          # Member may have been deleted between form open and keystroke; fall back to new changeset.
          case Provider.get_staff_member(staff_id) do
            {:ok, staff} ->
              Provider.change_staff_member(staff, params)

            {:error, :not_found} ->
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
  def handle_event("delete_member", %{"id" => staff_id}, socket) do
    # Accounts orchestrates: it deletes the Provider row AND durably drops :staff
    # when no other active linked row remains (#972), atomically.
    case Accounts.remove_staff_member(staff_id) do
      {:ok, deleted} ->
        {:noreply,
         socket
         |> stream_delete_by_dom_id(:team_members, "team_members-#{staff_id}")
         |> update_staff_count(max(0, socket.assigns.staff_count - 1))
         |> heal_after_self_delete({:ok, deleted})
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

      {:error, :invitation_emission_failed} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Staff member created, but the invitation could not be sent. Try resending from the team list.")
         )}

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
        staff_views =
          socket.assigns.current_scope.provider.id
          |> fetch_staff_members()
          |> StaffMemberPresenter.to_admin_view_list()

        {:noreply,
         socket
         |> stream(:team_members, staff_views, reset: true)
         |> update_staff_count(length(staff_views))
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
        {:noreply, assign(socket, staff_form: to_form(changeset, as: :staff_member_schema))}
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
         |> assign(staff_form: to_form(changeset, as: :staff_member_schema))
         |> put_flash(:error, gettext("Please fix the errors below."))}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> assign(show_staff_form: false, editing_staff_id: nil)
         |> put_flash(:error, gettext("Staff member no longer exists."))}
    end
  end

  defp update_staff_count(socket, count) do
    assign(socket, staff_count: count)
  end

  defp fetch_staff_members(provider_id) do
    {:ok, members} = Provider.list_staff_members(provider_id)
    members
  end

  defp upload_headshot(socket, provider_id) do
    Uploads.consume_single_upload(socket, :headshot, "headshots", provider_id)
  end

  defp atomize_staff_params(params) do
    %{
      first_name: params["first_name"],
      last_name: params["last_name"],
      role: Params.presence(params["role"]),
      email: Params.presence(params["email"]),
      bio: Params.presence(params["bio"]),
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
    amount = Params.presence(params["rate_amount"])
    currency = Params.presence(params["rate_currency"]) || "EUR"

    case amount && constructor.(amount, currency) do
      {:ok, pay_rate} -> pay_rate
      _ -> :invalid
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
            <h2 class="text-xl font-semibold text-hero-charcoal">
              {gettext("Team & Provider Profiles")}
            </h2>
            <p class="text-sm text-hero-grey-500">
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
      </div>
    </.pv_dashboard_shell>
    """
  end
end
