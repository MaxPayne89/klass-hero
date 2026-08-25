defmodule KlassHeroWeb.Admin.MessagesLive do
  @moduledoc """
  Read-only browser over every conversation on the platform (#744).

  Monitoring, not moderation: this surface lists and reads, and offers no action
  that writes. It never uses `KlassHeroWeb.MessagingLiveHelper` — that macro injects
  `send_message`, `validate` and `cancel-upload` handlers into whatever module uses
  it, so adopting it here would wire a write path into a read-only screen even if no
  markup triggered it. The thread is composed from `message_bubble/1`, which is
  purely presentational, rather than from `conversation_show/1`, which requires a
  form and renders a composer.

  Authorization is `Messaging.authorize_admin/1` inside the context, reached through
  `monitor_conversations/2` and `get_monitored_conversation/3`. The router's
  `:require_admin` on_mount stays as defence in depth, not as the guarantee.
  """

  use KlassHeroWeb, :live_view

  # Only the presentational bubble — importing the whole module would put
  # `message_input/1` and `conversation_show/1` in scope on a read-only screen.
  import KlassHeroWeb.MessagingComponents, only: [message_bubble: 1]

  alias KlassHero.Admin.Queries
  alias KlassHero.Messaging
  alias KlassHeroWeb.Admin.Components.SearchableSelect
  alias KlassHeroWeb.Theme

  @page_size 25

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:fluid?, false)
     |> assign(:live_resource, nil)
     |> assign(:page_title, gettext("Messages"))
     |> assign(:providers, Queries.list_providers_for_select())
     |> assign(:provider_id, nil)
     |> assign(:has_more, false)
     |> assign(:cursor, nil)
     |> stream(:conversations, [])}
  end

  # @current_url is assigned by Backpex.InitAssigns' handle_params hook, attached in
  # the :admin_custom live_session.
  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, params) do
    provider_id = normalize_uuid(params["provider_id"])

    socket
    |> assign(:page_title, gettext("Messages"))
    |> assign(:provider_id, provider_id)
    |> assign(:selected_provider, find_provider(socket.assigns.providers, provider_id))
    |> load_page(reset: true)
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         {:ok, result} <-
           Messaging.get_monitored_conversation(socket.assigns.current_scope, uuid) do
      socket
      |> assign(:conversation, result.conversation)
      |> assign(:sender_names, result.sender_names)
      |> assign(:provider_name, provider_name(result.conversation.provider_id))
      |> assign(:page_title, gettext("Conversation"))
      |> stream(:messages, Enum.reverse(result.messages), reset: true)
    else
      _ ->
        socket
        |> put_flash(:error, gettext("Conversation not found."))
        |> push_navigate(to: ~p"/admin/messages")
    end
  end

  @impl true
  def handle_event("load_more", _params, socket) do
    {:noreply, load_page(socket, reset: false)}
  end

  @impl true
  def handle_info({:select, "provider_id", selected}, socket) do
    params = if selected, do: %{"provider_id" => selected.id}, else: %{}

    {:noreply, push_patch(socket, to: ~p"/admin/messages?#{params}")}
  end

  defp load_page(socket, reset: reset?) do
    opts =
      [limit: @page_size, provider_id: socket.assigns.provider_id]
      |> maybe_cursor(reset?, socket.assigns.cursor)

    case Messaging.monitor_conversations(socket.assigns.current_scope, opts) do
      {:ok, conversations, has_more} ->
        socket
        |> stream(:conversations, conversations, reset: reset?)
        |> assign(:has_more, has_more)
        |> assign(:cursor, cursor_from(conversations))
        |> assign(:conversations_empty?, reset? and conversations == [])

      {:error, :unauthorized} ->
        socket
        |> put_flash(:error, gettext("You don't have access to that page."))
        |> push_navigate(to: ~p"/")
    end
  end

  defp maybe_cursor(opts, true, _cursor), do: opts
  defp maybe_cursor(opts, false, nil), do: opts
  defp maybe_cursor(opts, false, cursor), do: Keyword.put(opts, :before, cursor)

  defp cursor_from([]), do: nil
  defp cursor_from(conversations), do: List.last(conversations).inserted_at

  defp find_provider(_providers, nil), do: nil
  defp find_provider(providers, provider_id), do: Enum.find(providers, &(&1.id == provider_id))

  # Row labels come from the dropdown's own list rather than a second query — it is
  # already loaded, and the filter and the rows then cannot disagree about a name.
  defp provider_label(providers, provider_id) do
    case find_provider(providers, provider_id) do
      %{label: label} -> label
      nil -> gettext("Unknown provider")
    end
  end

  defp provider_name(provider_id) do
    provider_id
    |> List.wrap()
    |> KlassHero.Provider.get_business_names()
    |> Map.get(provider_id)
  end

  # A hand-typed `?provider_id=` must not reach Ecto as a malformed UUID.
  defp normalize_uuid(nil), do: nil

  defp normalize_uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> uuid
      :error -> nil
    end
  end

  defp conversation_label(%{type: :program_broadcast}), do: gettext("Broadcast")
  defp conversation_label(%{type: :direct}), do: gettext("Direct")

  defp participant_count(%{participants: participants}) when is_list(participants), do: length(participants)

  defp participant_count(_conversation), do: 0
end
