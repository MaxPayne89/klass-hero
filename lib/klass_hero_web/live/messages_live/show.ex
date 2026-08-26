defmodule KlassHeroWeb.MessagesLive.Show do
  @moduledoc """
  LiveView for displaying a conversation with messages (parent view).

  Features:
  - Displays messages in chronological order
  - Real-time message updates via PubSub
  - Message input and sending
  - Auto-mark as read on view
  - Stream-based collection for memory efficiency
  """

  use KlassHeroWeb, :live_view
  use KlassHeroWeb.MessagingLiveHelper, :show

  import KlassHeroWeb.MessagingComponents

  @impl true
  def mount(%{"provider_id" => provider_id} = params, _session, socket) do
    {:ok, socket} =
      MessagingLiveHelper.mount_compose(
        socket,
        [provider_id: provider_id, program_id: params["program_id"]],
        back_path: ~p"/messages",
        navigate_base: "/messages"
      )

    {:ok, assign(socket, active_nav: :messages)}
  end

  def mount(%{"id" => conversation_id}, _session, socket) do
    {:ok, socket} =
      MessagingLiveHelper.mount_conversation_show(socket, conversation_id,
        back_path: ~p"/messages",
        variant: :parent
      )

    {:ok, assign(socket, active_nav: :messages)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.conversation_show
      variant={:parent}
      streams={@streams}
      messages_empty?={@messages_empty?}
      page_title={@page_title}
      broadcast?={@broadcast?}
      internal?={@internal?}
      back_path={@back_path}
      form={@form}
      current_user_id={@current_scope.user.id}
      sender_names={@sender_names}
      provider_user_ids={@provider_user_ids}
      provider_name={@provider_name}
      uploads={@uploads}
    />
    """
  end
end
