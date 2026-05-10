defmodule KlassHeroWeb.Staff.MessagesLive.Index do
  @moduledoc """
  LiveView for displaying the staff member's conversation list.

  Shares layout and behavior with the provider version via
  `MessagingComponents.conversation_index/1` with `:provider` variant.
  """

  use KlassHeroWeb, :live_view
  use KlassHeroWeb.MessagingLiveHelper, :index

  import KlassHeroWeb.MessagingComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket} =
      MessagingLiveHelper.mount_conversation_index(socket, navigate_base: "/staff/messages")

    {:ok, assign(socket, active_nav: :messages)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.conversation_index
      variant={:provider}
      streams={@streams}
      conversations_empty?={@conversations_empty?}
      navigate_base={@navigate_base}
    />
    """
  end
end
