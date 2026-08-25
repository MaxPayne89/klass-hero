defmodule KlassHeroWeb.Provider.MessagesLive.Index do
  @moduledoc """
  LiveView for displaying the provider's conversation list.

  Shares layout and behavior with the parent version via
  `MessagingComponents.conversation_index/1` with `:provider` variant.
  """

  use KlassHeroWeb, :live_view
  use KlassHeroWeb.MessagingLiveHelper, :index

  import KlassHeroWeb.MessagingComponents
  import KlassHeroWeb.ProviderComponents, only: [provider_message_tabs: 1]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket} =
      MessagingLiveHelper.mount_conversation_index(socket, navigate_base: "/provider/messages")

    {:ok, assign(socket, active_nav: :messages, page_title: gettext("Comms"))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.conversation_index
      variant={:provider}
      streams={@streams}
      conversations_empty?={@conversations_empty?}
      navigate_base={@navigate_base}
    >
      <:tabs>
        <.provider_message_tabs current_tab={:inbox} />
      </:tabs>
    </.conversation_index>
    """
  end
end
