defmodule KlassHeroWeb.Admin.EmailsLive do
  @moduledoc """
  Admin inbox for inbound emails received via Resend webhooks.

  Provides list/filter, detail with sanitized HTML, and reply functionality.
  """

  use KlassHeroWeb, :live_view

  alias KlassHero.Messaging
  alias KlassHeroWeb.Theme

  @impl true
  def mount(_params, _session, socket) do
    unread_count = Messaging.count_inbound_emails_by_status(:unread)

    {:ok,
     socket
     |> assign(:fluid?, false)
     |> assign(:live_resource, nil)
     |> assign(:page_title, gettext("Emails"))
     |> assign(:unread_email_count, unread_count)
     |> assign(:status_filter, nil)
     |> assign(:allow_images, false)}
  end

  # @current_url is assigned by Backpex.InitAssigns' handle_params hook, attached
  # in the :admin_custom live_session.
  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, gettext("Emails"))
    |> load_emails()
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    reader_id = socket.assigns.current_scope.user.id

    with {:ok, uuid} <- Ecto.UUID.cast(id),
         {:ok, email} <- Messaging.get_inbound_email(uuid, mark_read: true, reader_id: reader_id) do
      {:ok, replies} = Messaging.list_email_replies(email.id)

      socket
      |> assign(:email, email)
      |> assign(
        :sanitized_html,
        Messaging.sanitize_email_html(email.body_html, allow_images: false)
      )
      |> stream(:replies, replies)
      |> assign(:allow_images, false)
      |> assign(:reply_form, to_form(%{"body" => ""}, as: :reply))
      |> assign(:page_title, email.subject)
      |> assign(:unread_email_count, Messaging.count_inbound_emails_by_status(:unread))
    else
      _ ->
        socket
        |> put_flash(:error, gettext("Email not found"))
        |> push_navigate(to: ~p"/admin/emails")
    end
  end

  @valid_status_filters ~w(unread read archived)

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    filter = parse_status_filter(status)

    {:noreply,
     socket
     |> assign(:status_filter, filter)
     |> load_emails()}
  end

  @impl true
  def handle_event("submit_reply", %{"reply" => %{"body" => body}}, socket) do
    trimmed_body = String.trim(body)

    if trimmed_body == "" do
      {:noreply, socket}
    else
      email = socket.assigns.email
      sent_by_id = socket.assigns.current_scope.user.id

      case Messaging.reply_to_inbound_email(email.id, trimmed_body, sent_by_id) do
        {:ok, reply} ->
          {:noreply,
           socket
           |> assign(:reply_form, to_form(%{"body" => ""}, as: :reply))
           |> stream_insert(:replies, reply)
           |> push_event("clear_message_input", %{})
           |> put_flash(:info, gettext("Reply sent successfully"))}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Failed to send reply"))}
      end
    end
  end

  @impl true
  def handle_event("retry_fetch", _params, socket) do
    email = socket.assigns.email

    with {:ok, updated_email} <-
           Messaging.update_inbound_email_content(email.id, %{content_status: "pending"}),
         {:ok, _job} <-
           Messaging.schedule_content_fetch(updated_email.id, updated_email.resend_id) do
      {:noreply,
       socket
       |> assign(:email, updated_email)
       |> put_flash(:info, gettext("Content fetch retrying..."))}
    else
      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to schedule retry"))}
    end
  end

  @impl true
  def handle_event("archive", _params, socket) do
    email = socket.assigns.email

    case Messaging.update_inbound_email_status(email.id, "archived") do
      {:ok, updated_email} ->
        {:noreply,
         socket
         |> assign(:email, updated_email)
         |> assign(:unread_email_count, Messaging.count_inbound_emails_by_status(:unread))
         |> put_flash(:info, gettext("Email archived"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to archive email"))}
    end
  end

  @impl true
  def handle_event("mark_unread", _params, socket) do
    email = socket.assigns.email

    case Messaging.update_inbound_email_status(email.id, "unread", %{
           read_by_id: nil,
           read_at: nil
         }) do
      {:ok, updated_email} ->
        {:noreply,
         socket
         |> assign(:email, updated_email)
         |> assign(:unread_email_count, Messaging.count_inbound_emails_by_status(:unread))
         |> put_flash(:info, gettext("Email marked as unread"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to mark email as unread"))}
    end
  end

  @impl true
  def handle_event("load_images", _params, socket) do
    email = socket.assigns.email
    sanitized_html = Messaging.sanitize_email_html(email.body_html, allow_images: true)

    {:noreply,
     socket
     |> assign(:allow_images, true)
     |> assign(:sanitized_html, sanitized_html)}
  end

  defp load_emails(socket) do
    opts =
      case socket.assigns.status_filter do
        nil -> []
        status -> [status: status]
      end

    {:ok, emails, _has_more} = Messaging.list_inbound_emails(opts)
    stream(socket, :emails, emails, reset: true)
  end

  defp parse_status_filter(status) when status in @valid_status_filters, do: String.to_existing_atom(status)

  defp parse_status_filter(_), do: nil

  defp status_badge_class(:unread), do: "badge-warning"
  defp status_badge_class(:read), do: "badge-ghost"
  defp status_badge_class(:archived), do: "badge-secondary"
  defp status_badge_class(_), do: ""

  defp reply_status_badge_class(:sending), do: "badge-info"
  defp reply_status_badge_class(:sent), do: "badge-success"
  defp reply_status_badge_class(:failed), do: "badge-error"
  defp reply_status_badge_class(_), do: ""

  defp format_received_at(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %d, %Y %H:%M")
  end

  defp format_received_at(_), do: ""

  defp translate_email_status(:unread), do: gettext("Unread")
  defp translate_email_status(:read), do: gettext("Read")
  defp translate_email_status(:archived), do: gettext("Archived")
  defp translate_email_status(status), do: status |> to_string() |> String.capitalize()

  defp translate_reply_status(:sending), do: gettext("Sending")
  defp translate_reply_status(:sent), do: gettext("Sent")
  defp translate_reply_status(:failed), do: gettext("Failed")
  defp translate_reply_status(status), do: status |> to_string() |> String.capitalize()
end
