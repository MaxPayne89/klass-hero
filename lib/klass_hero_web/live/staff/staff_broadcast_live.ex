defmodule KlassHeroWeb.Staff.StaffBroadcastLive do
  @moduledoc """
  LiveView for staff members to send program broadcast messages.

  Mirrors the provider broadcast flow but uses the staff member's associated
  provider for entitlement checks and redirects to staff routes.
  """

  use KlassHeroWeb, :live_view

  alias KlassHero.Messaging
  alias KlassHero.Messaging.Attachment
  alias KlassHero.ProgramCatalog
  alias KlassHero.Provider
  alias KlassHeroWeb.MessagingComponents
  alias KlassHeroWeb.MessagingLiveHelper

  require Logger

  @impl true
  def mount(%{"program_id" => program_id}, _session, socket) do
    staff_member = socket.assigns.current_scope.staff_member

    case Provider.get_provider_profile(staff_member.provider_id) do
      {:ok, provider} ->
        mount_broadcast_form(socket, provider, staff_member, program_id)

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Provider not found"))
         |> push_navigate(to: ~p"/staff/dashboard")}

      {:error, reason} ->
        Logger.error("Failed to load provider for staff broadcast",
          reason: inspect(reason),
          provider_id: staff_member.provider_id
        )

        {:ok,
         socket
         |> put_flash(:error, gettext("Something went wrong. Please try again."))
         |> push_navigate(to: ~p"/staff/dashboard")}
    end
  end

  defp mount_broadcast_form(socket, provider, staff_member, program_id) do
    case ProgramCatalog.get_program_by_id(program_id) do
      {:ok, program} ->
        if program.provider_id == provider.id and staff_assigned?(staff_member, program) do
          form = to_form(%{"subject" => "", "content" => ""})

          socket =
            socket
            |> assign(:page_title, gettext("Send Broadcast"))
            |> assign(:active_nav, :messages)
            |> assign(:program, program)
            |> assign(:provider, provider)
            |> assign(:form, form)
            |> assign(:sending, false)
            |> allow_upload(:attachments,
              accept: ~w(.jpg .jpeg .png .gif .webp),
              max_entries: Attachment.max_per_message(),
              max_file_size: Attachment.max_file_size_bytes()
            )

          {:ok, socket}
        else
          {:ok,
           socket
           |> put_flash(:error, gettext("You are not assigned to this program"))
           |> push_navigate(to: ~p"/staff/dashboard")}
        end

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Program not found"))
         |> push_navigate(to: ~p"/staff/dashboard")}
    end
  end

  defp staff_assigned?(staff_member, program) do
    staff_member.tags == [] or program.category in staff_member.tags
  end

  @impl true
  def handle_event("validate", %{"subject" => subject, "content" => content}, socket) do
    form = to_form(%{"subject" => subject, "content" => content})
    {:noreply, assign(socket, :form, form)}
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, MessagingLiveHelper.cancel_attachment_upload(socket, ref)}
  end

  @impl true
  def handle_event("send_broadcast", %{"subject" => _, "content" => _} = params, socket) do
    case MessagingLiveHelper.consume_and_validate_broadcast(socket, params) do
      {:ok, subject, content, attachments} ->
        send_broadcast(socket, subject, content, attachments)

      :empty ->
        {:noreply, put_flash(socket, :error, gettext("Message content is required"))}
    end
  end

  defp send_broadcast(socket, subject, content, attachments) do
    socket = assign(socket, :sending, true)
    scope = socket.assigns.current_scope
    program_id = socket.assigns.program.id
    provider_id = socket.assigns.provider.id

    opts =
      [provider_id: provider_id, skip_entitlement_check: true, attachments: attachments] ++
        if(subject == "", do: [], else: [subject: subject])

    case Messaging.broadcast_to_program(scope, program_id, content, opts) do
      {:ok, conversation, _message, recipient_count} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           gettext("Broadcast sent to %{count} parents", count: recipient_count)
         )
         |> push_navigate(to: ~p"/staff/messages/#{conversation.id}")}

      {:error, :no_enrollments} ->
        {:noreply,
         socket
         |> assign(:sending, false)
         |> put_flash(:error, gettext("No parents are enrolled in this program"))}

      {:error, reason}
      when reason in [
             :too_many_attachments,
             :invalid_attachment_type,
             :attachment_too_large,
             :upload_failed
           ] ->
        {:noreply,
         socket
         |> assign(:sending, false)
         |> put_flash(:error, MessagingLiveHelper.upload_error_message(reason))}

      {:error, reason} ->
        Logger.error("Failed to send staff broadcast",
          reason: inspect(reason),
          program_id: program_id,
          provider_id: provider_id
        )

        {:noreply,
         socket
         |> assign(:sending, false)
         |> put_flash(:error, gettext("Failed to send broadcast"))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 py-8">
      <div class="max-w-2xl mx-auto px-4">
        <div class="bg-white rounded-lg shadow-sm">
          <%!-- Header --%>
          <div class="px-6 py-4 border-b border-gray-200">
            <div class="flex items-center gap-3">
              <.link navigate={~p"/staff/dashboard"} class="text-gray-500 hover:text-gray-700">
                <.icon name="hero-arrow-left" class="w-6 h-6" />
              </.link>
              <div>
                <h1 class="text-xl font-semibold text-gray-900">{gettext("Send Broadcast")}</h1>
                <p class="text-sm text-gray-500">{@program.title}</p>
              </div>
            </div>
          </div>

          <%!-- Form --%>
          <.form
            for={@form}
            phx-change="validate"
            phx-submit="send_broadcast"
            id="staff-broadcast-form"
            class="p-6 space-y-6"
          >
            <div>
              <label for="subject" class="block text-sm font-medium text-gray-700 mb-1">
                {gettext("Subject")} <span class="text-gray-400">({gettext("optional")})</span>
              </label>
              <input
                type="text"
                name="subject"
                id="subject"
                value={Phoenix.HTML.Form.input_value(@form, :subject)}
                class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-hero-blue-500 focus:border-transparent"
                placeholder={gettext("e.g., Important Update")}
              />
            </div>

            <div>
              <label for="content" class="block text-sm font-medium text-gray-700 mb-1">
                {gettext("Message")} <span class="text-red-500">*</span>
              </label>
              <textarea
                name="content"
                id="content"
                rows="6"
                class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-hero-blue-500 focus:border-transparent resize-none"
                placeholder={gettext("Write your message to all enrolled parents...")}
              >{Phoenix.HTML.Form.input_value(@form, :content)}</textarea>
            </div>

            <MessagingComponents.attachment_uploader uploads={@uploads} />

            <div class="bg-amber-50 border border-amber-200 rounded-lg p-4">
              <div class="flex gap-3">
                <.icon
                  name="hero-information-circle"
                  class="w-5 h-5 text-amber-500 flex-shrink-0 mt-0.5"
                />
                <p class="text-sm text-amber-800">
                  {gettext(
                    "This message will be sent to all parents with active enrollments in this program."
                  )}
                </p>
              </div>
            </div>

            <div class="flex justify-end gap-3">
              <.link
                navigate={~p"/staff/dashboard"}
                class="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50"
              >
                {gettext("Cancel")}
              </.link>
              <button
                id="send-broadcast-btn"
                type="submit"
                disabled={@sending}
                class={[
                  "px-4 py-2 text-sm font-medium text-white rounded-lg flex items-center gap-2",
                  "bg-hero-blue-600 hover:bg-hero-blue-700",
                  "disabled:opacity-50 disabled:cursor-not-allowed"
                ]}
              >
                <span :if={@sending}>{gettext("Sending...")}</span>
                <span :if={!@sending}>{gettext("Send Broadcast")}</span>
              </button>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end
end
