defmodule KlassHeroWeb.Staff.StaffDashboardLive do
  use KlassHeroWeb, :live_view

  alias KlassHero.Accounts
  alias KlassHero.Accounts.Scope
  alias KlassHero.Enrollment
  alias KlassHero.Messaging
  alias KlassHero.Provider
  alias KlassHero.Provider.Domain.ReadModels.StaffProgramAccess
  alias KlassHeroWeb.Helpers.StaffLiveHelpers
  alias KlassHeroWeb.Presenters.StaffMemberPresenter
  alias KlassHeroWeb.Theme

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    staff_member = socket.assigns.current_scope.staff_member

    {:ok, memberships} =
      Provider.list_active_staff_memberships(socket.assigns.current_scope.user.id)

    # memberships read model carries id + business_name — no separate profile lookup needed.
    case Enum.find(memberships, &(&1.provider_id == staff_member.provider_id)) do
      %{provider_id: provider_id, business_name: business_name} ->
        {programs, program_access} = StaffLiveHelpers.load_assigned_programs(staff_member)

        socket =
          socket
          |> assign(:page_title, gettext("Staff Dashboard"))
          |> assign(:active_nav, :home)
          |> assign(:provider, %{id: provider_id, business_name: business_name})
          |> assign(:memberships, memberships)
          |> assign(:staff_member, staff_member)
          |> assign(:self_view, StaffMemberPresenter.to_self_view(staff_member))
          |> assign(:program_access, program_access)
          |> assign(:programs_empty?, programs == [])
          |> assign(:provider?, Scope.provider?(socket.assigns.current_scope))
          |> assign(:upgrade_confirm?, false)
          |> assign(:show_roster, false)
          |> assign(:roster_entries, [])
          |> assign(:roster_program_name, nil)
          |> assign(:roster_program_id, nil)
          |> assign(:can_message?, false)
          |> assign(:roster_enrolled_count, 0)
          |> stream(:programs, programs)

        {:ok, socket}

      nil ->
        {:ok,
         socket
         |> put_flash(
           :error,
           gettext("The provider associated with your account could not be found.")
         )
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("request_provider_upgrade", _params, socket) do
    {:noreply, assign(socket, upgrade_confirm?: true)}
  end

  @impl true
  def handle_event("confirm_provider_upgrade", _params, socket) do
    case Accounts.upgrade_to_provider(socket.assigns.current_scope.user) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Welcome aboard! Let's set up your provider profile."))
         |> push_navigate(to: ~p"/provider/complete-profile")}

      {:error, :already_provider} ->
        # Stale tab: upgraded elsewhere — re-converge the UI.
        {:noreply,
         socket
         |> assign(provider?: true, upgrade_confirm?: false)
         |> put_flash(:info, gettext("You already have a provider profile."))}

      {:error, %Ecto.Changeset{} = changeset} ->
        # Log errors only — changeset.changes contains user's name/email (no Inspect redaction).
        Logger.error("Failed to upgrade staff user to provider",
          user_id: socket.assigns.current_scope.user.id,
          errors: inspect(changeset.errors)
        )

        {:noreply, upgrade_failed_flash(socket)}

      {:error, reason} ->
        Logger.error("Failed to upgrade staff user to provider",
          user_id: socket.assigns.current_scope.user.id,
          reason: inspect(reason)
        )

        {:noreply, upgrade_failed_flash(socket)}
    end
  end

  @impl true
  def handle_event("cancel_provider_upgrade", _params, socket) do
    {:noreply, assign(socket, upgrade_confirm?: false)}
  end

  @impl true
  def handle_event("view_roster", %{"id" => program_id} = params, socket) do
    if StaffProgramAccess.authorized?(socket.assigns.program_access, program_id) do
      roster = Enrollment.list_program_enrollments(program_id)
      can_message? = Messaging.can_initiate_messaging?(%{provider: socket.assigns.provider})
      enrolled_count = Enum.count(roster, &(&1.status == :confirmed))

      {:noreply,
       assign(socket,
         show_roster: true,
         roster_program_name: Map.get(params, "title", program_id),
         roster_program_id: program_id,
         roster_entries: roster,
         can_message?: can_message?,
         roster_enrolled_count: enrolled_count
       )}
    else
      {:noreply, put_flash(socket, :error, gettext("Unauthorized"))}
    end
  end

  @impl true
  def handle_event("close_roster", _params, socket) do
    {:noreply,
     assign(socket,
       show_roster: false,
       roster_entries: [],
       roster_program_name: nil,
       roster_program_id: nil,
       can_message?: false,
       roster_enrolled_count: 0
     )}
  end

  @impl true
  def handle_event("send_message_to_parent", %{"parent-user-id" => parent_user_id}, socket) do
    cond do
      not socket.assigns.can_message? ->
        {:noreply, put_flash(socket, :error, gettext("Upgrade your plan to send messages."))}

      not roster_confirmed?(socket.assigns.roster_entries, parent_user_id) ->
        {:noreply, put_flash(socket, :error, gettext("Cannot message this parent."))}

      true ->
        create_staff_conversation(socket, parent_user_id)
    end
  end

  @impl true
  def handle_event("switch_employer", %{"provider-id" => provider_id}, socket) do
    user_id = socket.assigns.current_scope.user.id

    # Both outcomes re-mount: success rebuilds for the new employment; failure (deactivated or
    # tampered id) re-resolves the scope so all stale assigns converge, not just the picker.
    with {:ok, uuid} <- Ecto.UUID.cast(provider_id),
         {:ok, :selected} <- Provider.select_staff_context(user_id, uuid) do
      {:noreply, push_navigate(socket, to: ~p"/staff/dashboard")}
    else
      _invalid_or_not_staffed ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("You're no longer on that team."))
         |> push_navigate(to: ~p"/staff/dashboard")}
    end
  end

  defp upgrade_failed_flash(socket) do
    put_flash(
      socket,
      :error,
      gettext("Could not set up your provider profile. Please try again.")
    )
  end

  defp roster_confirmed?(roster_entries, parent_user_id) do
    Enum.any?(roster_entries, fn entry ->
      entry.parent_user_id == parent_user_id and entry.status == :confirmed
    end)
  end

  defp create_staff_conversation(socket, parent_user_id) do
    scope = socket.assigns.current_scope
    provider_id = socket.assigns.provider.id

    case Messaging.create_direct_conversation(scope, provider_id, parent_user_id, skip_entitlement_check: true) do
      {:ok, conversation} ->
        {:noreply, push_navigate(socket, to: ~p"/staff/messages/#{conversation.id}")}

      {:error, reason} ->
        Logger.error("Failed to create direct conversation from staff roster",
          reason: inspect(reason),
          provider_id: provider_id,
          parent_user_id: parent_user_id
        )

        {:noreply, put_flash(socket, :error, gettext("Could not start conversation. Please try again."))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="staff-dashboard" class="max-w-4xl mx-auto px-4 py-6">
      <div id="business-name" class="mb-6">
        <h1 class={Theme.typography(:page_title)}>
          {@provider.business_name}
        </h1>
        <p class={Theme.typography(:body)}>
          {gettext("Welcome, %{name}", name: @staff_member.first_name)}
        </p>
        <p
          :if={@self_view.rate_label}
          id="staff-rate-label"
          class="text-sm text-hero-grey-600 mt-1"
        >
          {gettext("Your pay rate")}: {@self_view.rate_label}
        </p>
        <details :if={length(@memberships) > 1} id="employer-picker" class="relative mt-2">
          <summary class={[
            "inline-flex cursor-pointer select-none list-none items-center gap-1",
            "text-sm font-medium text-brand hover:text-brand/80"
          ]}>
            <.icon name="hero-building-storefront-mini" class="w-4 h-4" />
            {gettext("Switch provider")}
            <.icon name="hero-chevron-down-mini" class="w-4 h-4" />
          </summary>
          <ul class={[
            "absolute left-0 z-10 mt-2 w-full max-w-xs rounded-lg",
            "border border-hero-grey-200 bg-white shadow-lg"
          ]}>
            <li :for={membership <- @memberships}>
              <button
                id={"employer-option-#{membership.provider_id}"}
                type="button"
                phx-click="switch_employer"
                phx-value-provider-id={membership.provider_id}
                class={[
                  "flex w-full items-center justify-between gap-2 px-4 py-3",
                  "text-left text-sm text-hero-charcoal hover:bg-hero-grey-50"
                ]}
              >
                {membership.business_name}
                <.icon
                  :if={membership.provider_id == @provider.id}
                  name="hero-check-mini"
                  class="w-4 h-4 text-brand"
                />
              </button>
            </li>
          </ul>
        </details>
        <.link
          :if={@provider?}
          id="cross-nav-provider-link"
          navigate={~p"/provider/dashboard"}
          class="inline-flex items-center gap-1 text-sm text-brand hover:text-brand/80 mt-2"
        >
          {gettext("Manage your provider profile")} →
        </.link>
      </div>

      <.kh_card :if={not @provider?} id="become-provider-cta" class="p-5 mt-6">
        <h2 class={Theme.typography(:card_title)}>
          {gettext("Become a provider")}
        </h2>
        <%= if @upgrade_confirm? do %>
          <div id="become-provider-confirm" class="mt-1">
            <p class="text-sm text-hero-grey-600">
              {gettext(
                "You'll get your own provider profile to fill in, and your account will open on your provider dashboard from now on. You stay on %{business}'s team.",
                business: @provider.business_name
              )}
            </p>
            <div class="flex flex-col gap-2 mt-4">
              <.kh_button
                id="become-provider-confirm-button"
                variant={:primary}
                size={:lg}
                class="w-full justify-center"
                phx-click="confirm_provider_upgrade"
                phx-disable-with={gettext("Setting up...")}
              >
                {gettext("Yes, become a provider")}
              </.kh_button>
              <.kh_button
                id="become-provider-cancel-button"
                variant={:ghost}
                size={:lg}
                class="w-full justify-center"
                phx-click="cancel_provider_upgrade"
              >
                {gettext("Not now")}
              </.kh_button>
            </div>
          </div>
        <% else %>
          <p class="text-sm text-hero-grey-600 mt-1">
            {gettext("Offer your own programs on Klass Hero — alongside your work for %{business}.",
              business: @provider.business_name
            )}
          </p>
          <.kh_button
            id="become-provider-cta-button"
            variant={:primary}
            size={:lg}
            class="w-full justify-center mt-4"
            phx-click="request_provider_upgrade"
          >
            {gettext("Become a provider")}
          </.kh_button>
        <% end %>
      </.kh_card>

      <div class="mt-8">
        <h2 class={Theme.typography(:section_title)}>
          {gettext("Assigned Programs")}
        </h2>

        <div :if={@programs_empty?} id="programs-empty-state" class="text-center py-8 text-zinc-500">
          {gettext("No programs assigned yet.")}
        </div>

        <div id="assigned-programs" phx-update="stream" class="mt-4 space-y-4">
          <div
            :for={{dom_id, program} <- @streams.programs}
            id={dom_id}
            class="p-4 bg-white rounded-lg shadow-sm border border-zinc-200"
          >
            <h3 class={Theme.typography(:card_title)}>{program.title}</h3>
            <p :if={program.category} class="text-sm text-zinc-500 mt-1">{program.category}</p>

            <div class="flex gap-2 mt-3">
              <.link
                id={"sessions-link-#{program.id}"}
                navigate={~p"/staff/sessions?program_id=#{program.id}"}
                class={[
                  "inline-flex items-center gap-1 px-3 py-1.5 text-sm font-medium",
                  "text-hero-blue-600 bg-hero-blue-50 hover:bg-hero-blue-100",
                  "rounded-md transition-colors"
                ]}
              >
                <.icon name="hero-calendar-days-mini" class="w-4 h-4" />
                {gettext("Sessions")}
              </.link>

              <button
                id={"roster-btn-#{program.id}"}
                phx-click="view_roster"
                phx-value-id={program.id}
                phx-value-title={program.title}
                class={[
                  "inline-flex items-center gap-1 px-3 py-1.5 text-sm font-medium",
                  "text-hero-grey-700 bg-hero-grey-100 hover:bg-hero-grey-200",
                  "rounded-md transition-colors"
                ]}
              >
                <.icon name="hero-user-group-mini" class="w-4 h-4" />
                {gettext("Roster")}
              </button>
            </div>
          </div>
        </div>
      </div>

      <%= if @show_roster do %>
        <div
          id="staff-roster-backdrop"
          class="fixed inset-0 z-50 bg-black/50"
          phx-click="close_roster"
        >
        </div>
        <div
          id="staff-roster-modal"
          class={[
            "fixed inset-x-4 top-[10%] z-50 mx-auto max-w-lg bg-white",
            "rounded-xl shadow-xl max-h-[80vh] overflow-y-auto"
          ]}
        >
          <div class="flex items-center justify-between p-4 border-b border-hero-grey-200">
            <h2 class="text-lg font-semibold text-hero-charcoal">
              {gettext("Roster: %{name}", name: @roster_program_name)}
            </h2>
            <div class="flex items-center gap-1">
              <%= if @can_message? and @roster_enrolled_count > 0 do %>
                <.link
                  id={"staff-broadcast-#{@roster_program_id}"}
                  navigate={~p"/staff/programs/#{@roster_program_id}/broadcast"}
                  title={gettext("Send Broadcast")}
                  aria-label={gettext("Send Broadcast")}
                  class={[
                    "p-2 rounded-lg transition-colors",
                    "text-hero-grey-400 hover:text-hero-charcoal hover:bg-hero-grey-100"
                  ]}
                >
                  <.icon name="hero-megaphone-mini" class="w-5 h-5" />
                </.link>
              <% else %>
                <button
                  id={"staff-broadcast-#{@roster_program_id}"}
                  type="button"
                  disabled
                  title={gettext("No enrolled parents")}
                  class="p-2 rounded-lg text-hero-grey-300 cursor-not-allowed"
                >
                  <.icon name="hero-megaphone-mini" class="w-5 h-5" />
                </button>
              <% end %>
              <button
                id="close-roster-btn"
                phx-click="close_roster"
                class="p-1 text-hero-grey-400 hover:text-hero-grey-600"
              >
                <.icon name="hero-x-mark" class="w-5 h-5" />
              </button>
            </div>
          </div>

          <div class="p-4">
            <%= if @roster_entries == [] do %>
              <p class="text-center text-hero-grey-500 py-4">
                {gettext("No enrollments yet.")}
              </p>
            <% else %>
              <ul class="divide-y divide-hero-grey-200">
                <%= for entry <- @roster_entries do %>
                  <li class="py-3 flex items-center justify-between">
                    <div>
                      <span class="font-medium text-hero-charcoal">
                        {Map.get(entry, :child_name, gettext("Unknown"))}
                      </span>
                    </div>
                    <div class="flex items-center gap-2">
                      <span class="text-sm text-hero-grey-500">
                        {Map.get(entry, :status, "")}
                      </span>
                      <%= if @can_message? and entry.status == :confirmed and entry.parent_user_id do %>
                        <button
                          id={"staff-msg-#{entry.enrollment_id}"}
                          type="button"
                          phx-click="send_message_to_parent"
                          phx-value-parent-user-id={entry.parent_user_id}
                          title={gettext("Send Message")}
                          aria-label={gettext("Send Message")}
                          class={[
                            "p-2 inline-flex rounded-lg transition-colors",
                            "text-hero-grey-400 hover:text-hero-charcoal hover:bg-hero-grey-100"
                          ]}
                        >
                          <.icon name="hero-chat-bubble-left-mini" class="w-5 h-5" />
                        </button>
                      <% else %>
                        <button
                          id={"staff-msg-#{entry.enrollment_id}"}
                          type="button"
                          disabled
                          title={staff_message_button_title(entry)}
                          aria-label={staff_message_button_title(entry)}
                          class="p-2 inline-flex rounded-lg text-hero-grey-300 cursor-not-allowed"
                        >
                          <.icon name="hero-chat-bubble-left-mini" class="w-5 h-5" />
                        </button>
                      <% end %>
                    </div>
                  </li>
                <% end %>
              </ul>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp staff_message_button_title(entry) do
    cond do
      entry.parent_user_id == nil -> gettext("Parent account not available")
      entry.status != :confirmed -> gettext("Enrollment not confirmed")
      true -> gettext("Send Message")
    end
  end
end
