defmodule KlassHeroWeb.Staff.MessagesLive.Show do
  @moduledoc """
  LiveView for displaying a conversation with messages (staff view).

  Shares layout and behavior with the provider version via
  `MessagingComponents.conversation_show/1` with `:provider` variant.
  """

  use KlassHeroWeb, :live_view
  use KlassHeroWeb.MessagingLiveHelper, :show

  import KlassHeroWeb.MessagingComponents

  @impl true
  def mount(%{"id" => conversation_id}, _session, socket) do
    {:ok, socket} =
      MessagingLiveHelper.mount_conversation_show(socket, conversation_id,
        back_path: ~p"/staff/messages",
        variant: :staff
      )

    {:ok, assign(socket, active_nav: :messages)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.conversation_show
      variant={:provider}
      streams={@streams}
      messages_empty?={@messages_empty?}
      page_title={@page_title}
      conversation={@conversation}
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
