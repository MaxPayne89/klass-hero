defmodule KlassHeroWeb.Provider.StaffConversationsLive do
  @moduledoc """
  Read-only view of the conversations a provider owns but is not part of — the
  threads their staff conduct with parents (#746).

  Oversight, not participation: this surface lists and reads, and offers no action
  that writes. Like `KlassHeroWeb.Admin.MessagesLive`, it never uses
  `KlassHeroWeb.MessagingLiveHelper` — that macro injects `send_message`, `validate`
  and `cancel-upload` handlers into whatever module uses it, and its
  `mount_conversation_show/3` marks a thread read on every connected mount. Adopting
  it here would wire both a write path and a read-receipt into a screen that must
  have neither, whatever the markup does.

  The thread is composed from `message_bubble/1`, which is purely presentational,
  rather than from `conversation_show/1`, which requires a form and always renders a
  composer for the `:provider` variant.

  The list, by contrast, *does* reuse `conversation_card/1`: that component matches
  on field names rather than a struct name, so a `StaffConversation` renders through
  the identical card as the owner's own inbox and the two cannot drift apart.

  Authorization is `Messaging.authorize_provider_owner/1` inside the context, reached
  through `list_staff_conversations/2` and `get_staff_conversation/3`. The router's
  `:require_provider` on_mount stays as defence in depth, not as the guarantee — it
  proves the scope owns *a* provider, never that it owns the thread being read.
  """

  use KlassHeroWeb, :live_view

  # Only the presentational pieces. Importing the whole module would put
  # `message_input/1` and `conversation_show/1` in scope on a read-only screen.
  import KlassHeroWeb.MessagingComponents,
    only: [conversation_card: 1, message_bubble: 1, provider_comms_shell: 1]

  import KlassHeroWeb.ProviderComponents, only: [provider_message_tabs: 1]

  alias KlassHero.Messaging
  alias KlassHeroWeb.Theme

  @page_size 25

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:active_nav, :messages)
     |> assign(:page_title, gettext("Staff conversations"))
     |> assign(:has_more, false)
     |> assign(:cursor, nil)
     # A StaffConversation has no `:id` — it is a query-shaped row, not a table row —
     # so the DOM id has to come from the conversation it describes.
     |> stream_configure(:conversations, dom_id: &"staff-conversations-#{&1.conversation_id}")
     |> stream(:conversations, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, gettext("Staff conversations"))
    |> load_page(reset: true)
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         {:ok, result} <- Messaging.get_staff_conversation(socket.assigns.current_scope, uuid) do
      socket
      |> assign(:conversation, result.conversation)
      |> assign(:sender_names, result.sender_names)
      |> assign(:page_title, gettext("Conversation"))
      |> stream(:messages, Enum.reverse(result.messages), reset: true)
    else
      _ ->
        socket
        |> put_flash(:error, gettext("Conversation not found."))
        |> push_navigate(to: ~p"/provider/messages/staff")
    end
  end

  @impl true
  def handle_event("load_more", _params, socket) do
    {:noreply, load_page(socket, reset: false)}
  end

  defp load_page(socket, reset: reset?) do
    opts = maybe_cursor([limit: @page_size], reset?, socket.assigns.cursor)

    case Messaging.list_staff_conversations(socket.assigns.current_scope, opts) do
      {:ok, conversations, has_more} ->
        socket
        |> stream(:conversations, conversations, reset: reset?)
        |> assign(:has_more, has_more)
        |> assign(:cursor, cursor_from(conversations))

      {:error, :unauthorized} ->
        socket
        |> put_flash(:error, gettext("You don't have access to that page."))
        |> push_navigate(to: ~p"/provider/messages")
    end
  end

  defp maybe_cursor(opts, true, _cursor), do: opts
  defp maybe_cursor(opts, false, nil), do: opts
  defp maybe_cursor(opts, false, cursor), do: Keyword.put(opts, :before, cursor)

  defp cursor_from([]), do: nil
  defp cursor_from(conversations), do: List.last(conversations).inserted_at

  defp thread_title(%{subject: subject}) when is_binary(subject) and subject != "", do: subject
  defp thread_title(%{type: :program_broadcast}), do: gettext("Broadcast")
  defp thread_title(_conversation), do: gettext("Conversation")
end
