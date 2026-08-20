defmodule KlassHeroWeb.Settings.ChildrenLive do
  use KlassHeroWeb, :live_view

  alias KlassHero.Family
  alias KlassHeroWeb.Helpers.FamilyHelpers
  alias KlassHeroWeb.Presenters.ChildPresenter
  alias KlassHeroWeb.Theme

  require Logger

  @consent_type "provider_data_sharing"

  @impl true
  def mount(_params, _session, socket) do
    case FamilyHelpers.get_parent_for_current_user(socket) do
      {:ok, parent} ->
        children = Family.get_children(parent.id)

        children_count = length(children)

        socket =
          socket
          |> assign(page_title: gettext("Children Profiles"), active_nav: :children)
          |> assign(parent_id: parent.id)
          |> assign(children_count: children_count)
          |> assign(children_empty?: children_count == 0)
          |> assign(delete_candidate: nil)
          |> assign(enrolled_programs: [])
          |> stream(:children, Enum.map(children, &child_view_data/1))

        {:ok, socket}

      {:error, :no_parent} ->
        socket =
          socket
          |> put_flash(:error, gettext("Please set up your parent profile to manage children."))
          |> redirect(to: ~p"/users/settings#profiles")

        {:ok, socket}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(show_modal: false)
    |> assign(child: nil)
    |> assign(form: nil)
    |> assign(consent_checked: false)
  end

  defp apply_action(socket, :new, _params) do
    changeset = Family.change_child()

    socket
    |> assign(show_modal: true)
    |> assign(child: nil)
    |> assign(form: to_form(changeset, as: :child))
    |> assign(consent_checked: false)
  end

  defp apply_action(socket, :edit, %{"child_id" => child_id}) do
    case Family.get_child_by_id(child_id) do
      {:ok, child} ->
        # Verify ownership via join table before editing.
        if Family.child_belongs_to_parent?(child.id, socket.assigns.parent_id) do
          changeset = Family.change_child(child, %{})
          consent = Family.child_has_active_consent?(child.id, @consent_type)

          socket
          |> assign(show_modal: true)
          |> assign(child: child)
          |> assign(form: to_form(changeset, as: :child))
          |> assign(consent_checked: consent)
        else
          socket
          |> put_flash(:error, gettext("You don't have permission to edit this child."))
          |> push_patch(to: ~p"/settings/children")
        end

      {:error, :not_found} ->
        socket
        |> put_flash(:error, gettext("Child not found."))
        |> push_patch(to: ~p"/settings/children")
    end
  end

  @impl true
  def handle_event("validate_child", %{"child" => child_params}, socket) do
    changeset =
      if socket.assigns.child do
        Family.change_child(socket.assigns.child, child_params)
      else
        Family.change_child(child_params)
      end
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :child))}
  end

  def handle_event("toggle_consent", %{"value" => "true"}, socket) do
    {:noreply, assign(socket, consent_checked: true)}
  end

  def handle_event("toggle_consent", _params, socket) do
    {:noreply, assign(socket, consent_checked: false)}
  end

  def handle_event("save_child", %{"child" => child_params}, socket) do
    save_child(socket, socket.assigns.live_action, child_params)
  end

  def handle_event("request_delete_child", %{"id" => child_id}, socket) do
    if Family.child_belongs_to_parent?(child_id, socket.assigns.parent_id) do
      case Family.prepare_child_deletion(child_id) do
        {:ok, :no_enrollments} ->
          do_delete_child(socket, child_id)

        {:ok, :has_enrollments, program_titles} ->
          {:noreply,
           socket
           |> assign(delete_candidate: child_id)
           |> assign(enrolled_programs: program_titles)}

        {:error, reason} ->
          Logger.error("[ChildrenLive] prepare_child_deletion failed: #{inspect(reason)}",
            child_id: child_id
          )

          {:noreply, put_flash(socket, :error, gettext("Could not check enrollments. Please try again."))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("You don't have permission to delete this child."))}
    end
  end

  # Guards against stale/crafted events with no delete_candidate.
  def handle_event("confirm_delete_child", _params, %{assigns: %{delete_candidate: nil}} = socket) do
    Logger.warning("[ChildrenLive] confirm_delete_child with nil delete_candidate")

    {:noreply, put_flash(socket, :error, gettext("This deletion request has expired. Please try again."))}
  end

  def handle_event("confirm_delete_child", _params, socket) do
    child_id = socket.assigns.delete_candidate
    do_delete_child(socket, child_id)
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply,
     socket
     |> assign(delete_candidate: nil)
     |> assign(enrolled_programs: [])}
  end

  defp do_delete_child(socket, child_id) do
    case Family.delete_child(child_id) do
      :ok ->
        new_count = socket.assigns.children_count - 1

        {:noreply,
         socket
         |> stream_delete_by_dom_id(:children, "children-#{child_id}")
         |> assign(children_count: new_count)
         |> assign(children_empty?: new_count == 0)
         |> assign(delete_candidate: nil)
         |> assign(enrolled_programs: [])
         |> put_flash(:info, gettext("Child removed successfully."))}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> assign(delete_candidate: nil)
         |> assign(enrolled_programs: [])
         |> put_flash(:error, gettext("Child not found."))}

      {:error, reason} ->
        Logger.error("Child deletion failed: #{inspect(reason)}", child_id: child_id)

        {:noreply,
         socket
         |> assign(delete_candidate: nil)
         |> assign(enrolled_programs: [])
         |> put_flash(:error, gettext("Could not remove child. Please try again."))}
    end
  end

  defp save_child(socket, mode, child_params) do
    changeset =
      build_changeset(mode, socket.assigns.child, child_params)
      |> Map.put(:action, :validate)

    if changeset.valid? do
      attrs = build_attrs(mode, child_params, socket.assigns.parent_id)

      case persist_child(mode, attrs, socket.assigns.child, consent_opts(socket)) do
        {:ok, child} ->
          handle_save_success(socket, mode, child)

        {:error, %Ecto.Changeset{} = cs} ->
          {:noreply, assign(socket, form: to_form(cs, as: :child))}

        {:error, {:validation_error, _errors}} ->
          {:noreply, put_flash(socket, :error, gettext("Please check the form for errors."))}

        {:error, reason} ->
          Logger.error("Unexpected error saving child: #{inspect(reason)}")

          {:noreply, put_flash(socket, :error, gettext("An unexpected error occurred. Please try again."))}
      end
    else
      {:noreply, assign(socket, form: to_form(changeset, as: :child))}
    end
  end

  defp build_changeset(:new, _child, params), do: Family.change_child(params)
  defp build_changeset(:edit, child, params), do: Family.change_child(child, params)

  defp build_attrs(:new, params, parent_id) do
    params |> atomize_keys() |> Map.put(:parent_id, parent_id)
  end

  defp build_attrs(:edit, params, _parent_id), do: atomize_keys(params)

  defp persist_child(:new, attrs, _child, opts), do: Family.create_child(attrs, opts)
  defp persist_child(:edit, attrs, child, opts), do: Family.update_child(child.id, attrs, opts)

  # The checkbox is not part of child_params — it lives in the consent_checked assign,
  # kept current by the separate "toggle_consent" event — so the intent has to be handed
  # to Family explicitly. Family then writes it in the same transaction as the child.
  defp consent_opts(socket) do
    [
      consents: %{@consent_type => socket.assigns.consent_checked},
      parent_id: socket.assigns.parent_id
    ]
  end

  defp handle_save_success(socket, mode, child) do
    socket =
      socket
      |> stream_insert(:children, child_view_data(child))
      |> put_flash(:info, child_saved_flash(mode))
      |> push_patch(to: ~p"/settings/children")

    socket =
      if mode == :new do
        new_count = socket.assigns.children_count + 1
        socket |> assign(children_count: new_count) |> assign(children_empty?: false)
      else
        socket
      end

    {:noreply, socket}
  end

  # No "saved, but consent failed" variant any more: the consent shares the child's
  # transaction, so reaching here means both landed. A consent failure takes the child
  # with it and is reported by save_child/3's error branch instead.
  defp child_saved_flash(:new), do: gettext("Child added successfully.")
  defp child_saved_flash(:edit), do: gettext("Child updated successfully.")

  defp child_view_data(child) do
    simple = ChildPresenter.to_simple_view(child)
    consent = Family.child_has_active_consent?(child.id, @consent_type)

    Map.merge(simple, %{
      date_of_birth: child.date_of_birth,
      emergency_contact: child.emergency_contact,
      support_needs: child.support_needs,
      allergies: child.allergies,
      consent_active: consent
    })
  end

  @allowed_keys ~w(first_name last_name date_of_birth emergency_contact support_needs allergies gender school_grade)a

  defp atomize_keys(params) when is_map(params) do
    for key <- @allowed_keys,
        Map.has_key?(params, to_string(key)),
        into: %{} do
      {key, coerce_value(key, Map.get(params, to_string(key)))}
    end
  end

  # Domain expects %Date{}, not a string.
  defp coerce_value(:date_of_birth, value) when is_binary(value) and value != "" do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end

  defp coerce_value(:school_grade, ""), do: nil

  defp coerce_value(:school_grade, value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp coerce_value(_key, value), do: value

  @impl true
  def render(assigns) do
    ~H"""
    <div class={["min-h-screen", Theme.bg(:muted)]}>
      <.page_header variant={:dark} size={:large} centered container_class="max-w-7xl mx-auto">
        <:title>{gettext("Children Profiles")}</:title>
        <:subtitle>{gettext("Manage your children's information and consents")}</:subtitle>
      </.page_header>

      <div class="max-w-4xl mx-auto p-4 space-y-4">
        <div class="flex items-center justify-between mb-4">
          <.link
            navigate={~p"/users/settings"}
            class={[
              "inline-flex items-center gap-1 text-sm font-medium",
              Theme.text_color(:primary),
              "hover:underline"
            ]}
          >
            <.icon name="hero-arrow-left" class="w-4 h-4" />
            {gettext("Back to Settings")}
          </.link>

          <.link
            id="add-child-btn"
            patch={~p"/settings/children/new"}
            class={[
              "inline-flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white",
              "bg-hero-blue-600 hover:bg-hero-blue-700",
              Theme.rounded(:lg),
              Theme.transition(:normal)
            ]}
          >
            <.icon name="hero-plus" class="w-4 h-4" />
            {gettext("Add Child")}
          </.link>
        </div>

        <%= if @children_empty? do %>
          <.empty_state
            icon="hero-user-group"
            title={gettext("No children yet")}
            description={gettext("Add your first child to get started with activities and programs.")}
            data_testid="no-children-state"
          >
            <:action>
              <.link
                patch={~p"/settings/children/new"}
                class={[
                  "inline-flex items-center gap-2 px-4 py-2 mt-4 text-sm font-semibold text-white",
                  "bg-hero-blue-600 hover:bg-hero-blue-700",
                  Theme.rounded(:lg),
                  Theme.transition(:normal)
                ]}
              >
                <.icon name="hero-plus" class="w-4 h-4" />
                {gettext("Add Child")}
              </.link>
            </:action>
          </.empty_state>
        <% end %>

        <div id="children-list" phx-update="stream">
          <div
            :for={{dom_id, child} <- @streams.children}
            id={dom_id}
            class={[
              Theme.bg(:surface),
              "shadow-sm border overflow-hidden",
              Theme.rounded(:xl),
              Theme.border_color(:light),
              "p-4"
            ]}
          >
            <div class="flex items-start justify-between">
              <div class="flex items-center gap-3">
                <div class={[
                  "w-12 h-12 rounded-full flex items-center justify-center text-white font-bold text-lg",
                  Theme.gradient(:primary)
                ]}>
                  {String.first(child.name)}
                </div>
                <div>
                  <h3 class={["font-semibold", Theme.text_color(:heading)]}>
                    {child.name}
                  </h3>
                  <p class="text-sm text-hero-grey-500">
                    {gettext("%{age} years old", age: child.age)}
                    <%= if child.date_of_birth do %>
                      <span class="mx-1">&bull;</span>
                      {Calendar.strftime(child.date_of_birth, "%B %d, %Y")}
                    <% end %>
                  </p>
                </div>
              </div>

              <div class="flex items-center gap-2">
                <.link
                  patch={~p"/settings/children/#{child.id}/edit"}
                  class={[
                    "p-2 text-hero-grey-400 hover:text-hero-blue-600",
                    Theme.rounded(:lg),
                    "hover:bg-hero-grey-50",
                    Theme.transition(:normal)
                  ]}
                  title={gettext("Edit")}
                >
                  <.icon name="hero-pencil-square" class="w-5 h-5" />
                </.link>
                <button
                  type="button"
                  phx-click="request_delete_child"
                  phx-value-id={child.id}
                  class={[
                    "p-2 text-hero-grey-400 hover:text-red-600",
                    Theme.rounded(:lg),
                    "hover:bg-red-50",
                    Theme.transition(:normal)
                  ]}
                  title={gettext("Delete")}
                >
                  <.icon name="hero-trash" class="w-5 h-5" />
                </button>
              </div>
            </div>

            <div class="mt-3 flex flex-wrap gap-2">
              <%= if child.consent_active do %>
                <span class={[
                  "inline-flex items-center gap-1 px-2 py-1 text-xs font-medium",
                  "bg-green-100 text-green-700",
                  Theme.rounded(:full)
                ]}>
                  <.icon name="hero-check-circle-mini" class="w-3 h-3" />
                  {gettext("Data sharing consent")}
                </span>
              <% end %>

              <%= if child.emergency_contact do %>
                <span class={[
                  "inline-flex items-center gap-1 px-2 py-1 text-xs font-medium",
                  "bg-blue-100 text-blue-700",
                  Theme.rounded(:full)
                ]}>
                  <.icon name="hero-phone-mini" class="w-3 h-3" />
                  {gettext("Emergency contact")}
                </span>
              <% end %>

              <%= if child.allergies do %>
                <span class={[
                  "inline-flex items-center gap-1 px-2 py-1 text-xs font-medium",
                  "bg-orange-100 text-orange-700",
                  Theme.rounded(:full)
                ]}>
                  <.icon name="hero-exclamation-triangle-mini" class="w-3 h-3" />
                  {gettext("Allergies")}
                </span>
              <% end %>

              <%= if child.support_needs do %>
                <span class={[
                  "inline-flex items-center gap-1 px-2 py-1 text-xs font-medium",
                  "bg-purple-100 text-purple-700",
                  Theme.rounded(:full)
                ]}>
                  <.icon name="hero-heart-mini" class="w-3 h-3" />
                  {gettext("Support needs")}
                </span>
              <% end %>
            </div>
          </div>
        </div>
      </div>

      <%= if @delete_candidate do %>
        <div
          id="delete-modal-backdrop"
          class="fixed inset-0 z-50 bg-black/50"
          phx-click="cancel_delete"
        >
        </div>
        <div
          id="delete-confirmation-modal"
          role="dialog"
          aria-modal="true"
          aria-labelledby="delete-confirmation-title"
          class={[
            "fixed inset-x-4 top-[20%] z-50 mx-auto max-w-md",
            Theme.bg(:surface),
            Theme.rounded(:xl),
            "shadow-xl p-6"
          ]}
          phx-click-away="cancel_delete"
        >
          <div class="flex items-center gap-3 mb-4">
            <div class="flex-shrink-0 w-10 h-10 rounded-full bg-red-100 flex items-center justify-center">
              <.icon name="hero-exclamation-triangle" class="w-5 h-5 text-red-600" />
            </div>
            <h3
              id="delete-confirmation-title"
              class={["text-lg font-semibold", Theme.text_color(:heading)]}
            >
              {gettext("Remove Child?")}
            </h3>
          </div>

          <p class={["text-sm mb-3", Theme.text_color(:body)]}>
            {gettext("This child is currently enrolled in the following programs:")}
          </p>

          <ul class="mb-4 space-y-1">
            <%= for title <- @enrolled_programs do %>
              <li class="flex items-center gap-2 text-sm text-hero-grey-700">
                <.icon name="hero-academic-cap-mini" class="w-4 h-4 text-hero-blue-500" />
                {title}
              </li>
            <% end %>
          </ul>

          <p class={["text-sm mb-4", Theme.text_color(:muted)]}>
            {gettext("Their enrollments will be cancelled. This action cannot be undone.")}
          </p>

          <div class="flex justify-end gap-3">
            <button
              type="button"
              id="cancel-delete-btn"
              phx-click="cancel_delete"
              class={[
                "px-4 py-2 text-sm font-medium text-hero-grey-700",
                "bg-hero-grey-100 hover:bg-hero-grey-200",
                Theme.rounded(:lg),
                Theme.transition(:normal)
              ]}
            >
              {gettext("Cancel")}
            </button>
            <button
              type="button"
              id="confirm-delete-btn"
              phx-click="confirm_delete_child"
              class={[
                "px-4 py-2 text-sm font-semibold text-white",
                "bg-red-600 hover:bg-red-700",
                Theme.rounded(:lg),
                Theme.transition(:normal)
              ]}
            >
              {gettext("Remove Child")}
            </button>
          </div>
        </div>
      <% end %>

      <%= if @show_modal do %>
        <div
          id="child-modal-backdrop"
          class="fixed inset-0 z-50 bg-black/50"
          phx-click={JS.patch(~p"/settings/children")}
        >
        </div>
        <div
          id="child-modal"
          class={[
            "fixed inset-x-4 top-[5%] z-50 mx-auto max-w-lg",
            Theme.bg(:surface),
            Theme.rounded(:xl),
            "shadow-xl max-h-[90vh] overflow-y-auto"
          ]}
          phx-click-away={JS.patch(~p"/settings/children")}
        >
          <div class="flex items-center justify-between p-4 border-b border-hero-grey-200">
            <h2 class={["text-lg font-semibold", Theme.text_color(:heading)]}>
              <%= if @live_action == :new do %>
                {gettext("Add Child")}
              <% else %>
                {gettext("Edit Child")}
              <% end %>
            </h2>
            <.link
              patch={~p"/settings/children"}
              class="p-1 text-hero-grey-400 hover:text-hero-grey-600"
            >
              <.icon name="hero-x-mark" class="w-5 h-5" />
            </.link>
          </div>

          <div class="p-4">
            <.form
              for={@form}
              id="child-form"
              phx-change="validate_child"
              phx-submit="save_child"
              class="space-y-4"
            >
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <.input
                  field={@form[:first_name]}
                  type="text"
                  label={gettext("First name")}
                  required
                />
                <.input
                  field={@form[:last_name]}
                  type="text"
                  label={gettext("Last name")}
                  required
                />
              </div>

              <.input
                field={@form[:date_of_birth]}
                type="date"
                label={gettext("Date of birth")}
                required
              />

              <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <.input
                  field={@form[:gender]}
                  type="select"
                  label={gettext("Gender")}
                  options={[
                    {gettext("Not specified"), "not_specified"},
                    {gettext("Male"), "male"},
                    {gettext("Female"), "female"},
                    {gettext("Diverse"), "diverse"}
                  ]}
                />

                <.input
                  field={@form[:school_grade]}
                  type="select"
                  label={gettext("School Grade (optional)")}
                  prompt={gettext("No grade")}
                  options={Enum.map(1..13, &{gettext("Klasse %{n}", n: &1), &1})}
                />
              </div>

              <.input
                field={@form[:emergency_contact]}
                type="text"
                label={gettext("Emergency contact")}
                placeholder={gettext("Phone number or name")}
              />

              <.input
                field={@form[:allergies]}
                type="textarea"
                label={gettext("Allergies")}
                placeholder={gettext("List any known allergies...")}
              />

              <.input
                field={@form[:support_needs]}
                type="textarea"
                label={gettext("Support needs")}
                placeholder={gettext("Any special accommodations or support needs...")}
              />

              <div class="border-t border-hero-grey-200 pt-4">
                <label class="flex items-start gap-3 cursor-pointer">
                  <input
                    type="checkbox"
                    id="consent-checkbox"
                    name="consent"
                    value="true"
                    checked={@consent_checked}
                    phx-click="toggle_consent"
                    class="mt-1 rounded border-2 border-hero-grey-300 text-hero-blue-600 focus:ring-2 focus:ring-hero-blue-500/20"
                  />
                  <div>
                    <span class="text-sm font-medium text-hero-black">
                      {gettext("Provider data sharing consent")}
                    </span>
                    <p class="text-xs text-hero-grey-500 mt-1">
                      {gettext(
                        "Allow activity providers to access this child's profile information for program participation."
                      )}
                    </p>
                  </div>
                </label>
              </div>

              <div class="flex justify-end gap-3 pt-4">
                <.link
                  patch={~p"/settings/children"}
                  class={[
                    "px-4 py-2 text-sm font-medium text-hero-grey-700",
                    "bg-hero-grey-100 hover:bg-hero-grey-200",
                    Theme.rounded(:lg),
                    Theme.transition(:normal)
                  ]}
                >
                  {gettext("Cancel")}
                </.link>
                <button
                  type="submit"
                  id="save-child-btn"
                  phx-disable-with={gettext("Saving...")}
                  class={[
                    "px-4 py-2 text-sm font-semibold text-white",
                    "bg-hero-blue-600 hover:bg-hero-blue-700",
                    Theme.rounded(:lg),
                    Theme.transition(:normal)
                  ]}
                >
                  <%= if @live_action == :new do %>
                    {gettext("Add Child")}
                  <% else %>
                    {gettext("Save Changes")}
                  <% end %>
                </button>
              </div>
            </.form>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
