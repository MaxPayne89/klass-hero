defmodule KlassHeroWeb.MessagingComponents do
  @moduledoc """
  UI components for the messaging system.
  """

  use Phoenix.Component
  use Gettext, backend: KlassHeroWeb.Gettext

  import KlassHeroWeb.UIComponents, only: [icon: 1]

  alias KlassHero.Messaging.Attachment
  alias KlassHeroWeb.MessagingLiveHelper
  alias KlassHeroWeb.Theme
  alias Phoenix.LiveView.JS

  @doc """
  Renders a conversation card for the conversation list.

  The displayed label is derived from `conversation.type`:
  - `:program_broadcast` — uses `program_name`, falling back to
    `gettext("Program Broadcast")` when the program row is missing.
  - everything else — uses `other_participant_name`, falling back to
    `gettext("Unknown")`.

  ## Attributes
  - id: DOM id for the card
  - summary: A `KlassHero.Messaging.ConversationSummary` read-table row, or a
    `KlassHero.Messaging.StaffConversation` read row. This component matches on field
    *names*, never on a struct name, so any row carrying them renders — that is
    deliberate, and it is what keeps the participant inbox and the owner's staff-
    conversations list from drifting apart visually (#746)
  - user_type: `:parent` or `:provider` — parents do not see the enrolled child names
  - navigate: Target URL for the `<.link navigate=...>` wrapper

  A row carrying a non-empty `staff_member_names` also renders a "via …" attribution
  line; a row without that field simply omits it.

  ## Examples

      <.conversation_card
        id="conv-123"
        summary={summary}
        user_type={:parent}
        navigate={~p"/messages/\#{summary.conversation_id}"}
      />

  """
  attr :id, :string, required: true
  attr :summary, :map, required: true
  attr :user_type, :atom, required: true, values: [:parent, :provider]
  attr :navigate, :string, default: nil

  def conversation_card(assigns) do
    assigns =
      assigns
      |> assign(:display_name, derive_display_name(assigns.summary))
      |> assign(:unread_count, assigns.summary.unread_count)
      |> assign(:child_names, visible_child_names(assigns.summary, assigns.user_type))
      |> assign(:staff_names, Map.get(assigns.summary, :staff_member_names, []))

    ~H"""
    <.link
      navigate={@navigate}
      id={@id}
      data-role="conversation-card"
      class={[
        "block p-4 hover:bg-hero-grey-50 transition-colors",
        @unread_count > 0 && "bg-hero-blue-50"
      ]}
    >
      <div class="flex items-start gap-3">
        <div class={[
          "w-12 h-12 rounded-full flex items-center justify-center text-white font-semibold text-lg flex-shrink-0",
          avatar_color(@display_name)
        ]}>
          {String.first(@display_name) |> String.upcase()}
        </div>

        <div class="flex-1 min-w-0">
          <div class="flex items-center justify-between gap-2">
            <h3 class={[
              "text-base truncate",
              @unread_count > 0 && ["font-semibold", Theme.text_color(:heading)],
              @unread_count == 0 && ["font-medium", Theme.text_color(:body)]
            ]}>
              {@display_name}
            </h3>
            <span
              data-role="conversation-timestamp"
              class={["text-xs flex-shrink-0", Theme.text_color(:muted)]}
            >
              {latest_message_timestamp(@summary)}
            </span>
          </div>
          <p :if={@child_names != []} class={["text-xs mt-0.5", Theme.text_color(:muted)]}>
            {gettext("for")} {Enum.join(@child_names, ", ")}
          </p>
          <p
            :if={@staff_names != []}
            data-role="staff-attribution"
            class={["text-xs mt-0.5", Theme.text_color(:muted)]}
          >
            {gettext("via")} {Enum.join(@staff_names, ", ")}
          </p>

          <div class="flex items-center justify-between gap-2 mt-1">
            <p class={[
              "text-sm truncate flex items-center gap-1",
              @unread_count > 0 && Theme.text_color(:body),
              @unread_count == 0 && Theme.text_color(:muted)
            ]}>
              <.icon
                :if={@summary.has_attachments}
                name="hero-camera-mini"
                class="w-4 h-4 flex-shrink-0"
              />
              {preview_content(@summary)}
            </p>
            <.unread_badge :if={@unread_count > 0} count={@unread_count} />
          </div>

          <.broadcast_badge :if={@summary.conversation_type == :program_broadcast} />
        </div>
      </div>
    </.link>
    """
  end

  # Parents see their own children's names everywhere else; on the inbox the label
  # is provider-side context ("Sarah Johnson for Emma, Liam").
  defp visible_child_names(_summary, :parent), do: []
  defp visible_child_names(summary, :provider), do: summary.enrolled_child_names

  @doc """
  Renders an unread message count badge.
  """
  attr :count, :integer, required: true

  def unread_badge(assigns) do
    ~H"""
    <span
      data-role="unread-count"
      class="inline-flex items-center justify-center min-w-5 h-5 px-1.5 text-xs font-semibold text-error-content bg-error rounded-full"
    >
      {min(@count, 99)}
    </span>
    """
  end

  @doc """
  Renders a broadcast indicator badge.
  """
  attr :class, :string, default: nil

  def broadcast_badge(assigns) do
    ~H"""
    <span class={["inline-flex items-center gap-1 mt-1 text-xs", @class || "text-hero-blue-600"]}>
      <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M11 5.882V19.24a1.76 1.76 0 01-3.417.592l-2.147-6.15M18 13a3 3 0 100-6M5.436 13.683A4.001 4.001 0 017 6h1.832c4.1 0 7.625-1.234 9.168-3v14c-1.543-1.766-5.067-3-9.168-3H7a3.988 3.988 0 01-1.564-.317z"
        />
      </svg>
      {gettext("Broadcast")}
    </span>
    """
  end

  @doc """
  Renders a message bubble.

  ## Attributes
  - id: DOM id
  - message: The message entity
  - is_own: Whether the current user sent this message
  - sender_name: Name of the sender

  """
  attr :id, :string, required: true
  attr :message, :map, required: true
  attr :is_own, :boolean, default: false
  attr :sender_name, :string, default: "Unknown"
  attr :provider_name, :string, default: nil
  attr :is_provider_side, :boolean, default: false

  def message_bubble(assigns) do
    ~H"""
    <div
      id={@id}
      data-role="message"
      class={["flex", @is_own && "justify-end", !@is_own && "justify-start"]}
    >
      <div class={[
        "max-w-[80%] rounded-2xl px-4 py-2",
        @is_own && "bg-hero-blue-600 text-white rounded-br-sm",
        !@is_own && [Theme.bg(:light), Theme.text_color(:heading), "rounded-bl-sm"]
      ]}>
        <p
          :if={!@is_own && @message.message_type != :system}
          id={"#{@id}-attribution"}
          data-provider-side={to_string(@is_provider_side)}
          class={["text-xs font-medium mb-1", Theme.text_color(:muted)]}
        >
          <%= if @is_provider_side && @provider_name do %>
            <span>{@provider_name}</span>
            <span class="font-normal">{" via #{@sender_name}"}</span>
          <% else %>
            {@sender_name}
          <% end %>
        </p>
        <p
          :if={@message.message_type == :system}
          class={["text-xs italic text-center", Theme.text_color(:muted)]}
        >
          {@message.content}
        </p>
        <p
          :if={@message.message_type != :system && @message.content}
          class="text-sm whitespace-pre-wrap break-words"
        >
          {@message.content}
        </p>
        <div
          :if={@message.attachments != []}
          class={[
            "grid gap-1 mt-1",
            if(length(@message.attachments) == 1, do: "grid-cols-1", else: "grid-cols-2")
          ]}
        >
          <img
            :for={attachment <- @message.attachments}
            src={attachment.file_url}
            alt={attachment.original_filename}
            loading="lazy"
            class="rounded-lg w-full h-auto max-h-64 object-cover"
          />
        </div>
        <p class={[
          "text-xs mt-1",
          @is_own && "text-white/80",
          !@is_own && Theme.text_color(:subtle)
        ]}>
          {format_message_time(@message.inserted_at)}
        </p>
      </div>
    </div>
    """
  end

  @doc """
  Renders attachment upload affordances for forms outside the chat dock.

  Three stacked sections: per-entry error list, preview chips with cancel +
  progress, and a labeled "Attach photo" trigger that opens the file picker.
  Designed to be embedded inside the caller's `<.form>`, sharing the live
  socket's `:attachments` upload. The caller owns the textarea and submit
  button.
  """
  attr :uploads, :any, required: true
  attr :label, :string, default: nil

  def attachment_uploader(assigns) do
    ~H"""
    <div class="space-y-2">
      <div :if={upload_errors(@uploads.attachments) != []}>
        <p
          :for={err <- upload_errors(@uploads.attachments)}
          class="text-xs text-red-600"
        >
          {upload_error_to_string(err)}
        </p>
      </div>
      <div
        :if={@uploads.attachments.entries != []}
        class="flex gap-2 overflow-x-auto"
      >
        <div
          :for={entry <- @uploads.attachments.entries}
          class="relative flex-shrink-0"
        >
          <.live_img_preview
            entry={entry}
            class={[
              "w-16 h-16 rounded-lg object-cover",
              upload_errors(@uploads.attachments, entry) != [] && "ring-2 ring-red-400"
            ]}
          />
          <button
            type="button"
            phx-click="cancel-upload"
            phx-value-ref={entry.ref}
            aria-label={gettext("Remove attachment")}
            class="absolute -top-1.5 -right-1.5 w-5 h-5 rounded-full bg-red-500 text-white flex items-center justify-center text-xs shadow-sm"
          >
            &times;
          </button>
          <div
            :if={entry.progress > 0 and entry.progress < 100}
            class="absolute bottom-0 left-0 right-0 h-1 bg-gray-200 rounded-b-lg overflow-hidden"
          >
            <div class="h-full bg-hero-blue-600 transition-all" style={"width: #{entry.progress}%"} />
          </div>
        </div>
      </div>
      <label
        for={@uploads.attachments.ref}
        class={[
          "inline-flex items-center gap-2 text-sm text-gray-600 hover:text-hero-blue-600 cursor-pointer",
          "has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-[var(--focus-ring)] has-[:focus-visible]:ring-offset-2"
        ]}
      >
        <.icon name="hero-paper-clip" class="w-5 h-5" />
        <span>{@label || gettext("Attach photo")}</span>
        <.live_file_input upload={@uploads.attachments} class="sr-only" />
      </label>
    </div>
    """
  end

  @doc """
  Renders a message input form with optional upload support.

  When `uploads` is provided, renders attachment previews, a file input button,
  and error display for upload validation errors.
  """
  attr :form, :map, required: true
  attr :disabled, :boolean, default: false
  attr :uploads, :any, default: nil

  def message_input(assigns) do
    ~H"""
    <div id="message-input-area" class={["border-t", Theme.border_color(:light), Theme.bg(:surface)]}>
      <div
        :if={@uploads && upload_errors(@uploads.attachments) != []}
        class="px-4 pt-2"
      >
        <p
          :for={err <- upload_errors(@uploads.attachments)}
          class="text-xs text-red-600"
        >
          {upload_error_to_string(err)}
        </p>
      </div>
      <div
        :if={@uploads && @uploads.attachments.entries != []}
        class="px-4 pt-3 flex gap-2 overflow-x-auto"
      >
        <div
          :for={entry <- @uploads.attachments.entries}
          class="relative flex-shrink-0"
        >
          <.live_img_preview
            entry={entry}
            class={[
              "w-16 h-16 rounded-lg object-cover",
              upload_errors(@uploads.attachments, entry) != [] && "ring-2 ring-red-400"
            ]}
          />
          <button
            type="button"
            phx-click="cancel-upload"
            phx-value-ref={entry.ref}
            aria-label={gettext("Remove attachment")}
            class="absolute -top-1.5 -right-1.5 w-5 h-5 rounded-full bg-red-500 text-white flex items-center justify-center text-xs shadow-sm"
          >
            &times;
          </button>
          <div
            :if={entry.progress > 0 and entry.progress < 100}
            class="absolute bottom-0 left-0 right-0 h-1 bg-gray-200 rounded-b-lg overflow-hidden"
          >
            <div class="h-full bg-hero-blue-600 transition-all" style={"width: #{entry.progress}%"} />
          </div>
        </div>
      </div>
      <.form
        for={@form}
        phx-submit="send_message"
        phx-change="validate"
        id="message-form"
        class="flex items-end gap-2 p-4"
      >
        <label
          :if={@uploads}
          for={@uploads.attachments.ref}
          class={[
            "w-10 h-10 flex items-center justify-center cursor-pointer transition-colors",
            "has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-[var(--focus-ring)] has-[:focus-visible]:ring-offset-2",
            Theme.text_color(:muted),
            "hover:text-hero-blue-600",
            Theme.rounded(:full)
          ]}
        >
          <.icon name="hero-paper-clip" class="w-5 h-5" />
          <span class="sr-only">{gettext("Attach files")}</span>
          <.live_file_input upload={@uploads.attachments} class="sr-only" />
        </label>
        <div class="flex-1">
          <textarea
            name="content"
            id="message-input"
            aria-label={gettext("Message")}
            rows="1"
            class={[
              "w-full px-4 py-2 border resize-none focus:outline-none focus:ring-2 focus:ring-[var(--focus-ring)] focus:border-transparent",
              Theme.border_color(:medium),
              Theme.rounded(:full)
            ]}
            placeholder={gettext("Type a message...")}
            phx-hook="AutoResizeTextarea"
            phx-mounted={JS.focus()}
            disabled={@disabled}
          >{Phoenix.HTML.Form.input_value(@form, :content)}</textarea>
        </div>
        <button
          type="submit"
          disabled={@disabled}
          data-role="send-message-btn"
          aria-label={gettext("Send message")}
          class={[
            "w-10 h-10 flex items-center justify-center bg-hero-blue-600 text-white hover:bg-hero-blue-700 transition-colors disabled:opacity-50 disabled:cursor-not-allowed",
            Theme.rounded(:full)
          ]}
        >
          <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8"
            />
          </svg>
        </button>
      </.form>
    </div>
    """
  end

  @doc """
  Renders the messages empty state.
  """
  def messages_empty_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center h-64 text-center px-4">
      <div class={["w-16 h-16 mb-4", Theme.text_color(:subtle)]}>
        <svg fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="1.5"
            d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"
          />
        </svg>
      </div>
      <h3 class={["text-lg font-medium", Theme.text_color(:heading)]}>
        {gettext("No messages yet")}
      </h3>
      <p class={["mt-1 text-sm", Theme.text_color(:muted)]}>
        {gettext("Send a message to start the conversation")}
      </p>
    </div>
    """
  end

  @doc """
  Renders the conversations empty state.

  ## Attributes
  - user_type: Either :parent or :provider to show appropriate copy
  """
  attr :user_type, :atom, default: :parent

  def conversations_empty_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center h-64 text-center px-4">
      <div class={["w-16 h-16 mb-4", Theme.text_color(:subtle)]}>
        <svg fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="1.5"
            d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4"
          />
        </svg>
      </div>
      <h3 class={["text-lg font-medium", Theme.text_color(:heading)]}>
        {gettext("No conversations yet")}
      </h3>
      <p class={["mt-1 text-sm", Theme.text_color(:muted)]}>
        {empty_state_message(@user_type)}
      </p>
    </div>
    """
  end

  defp empty_state_message(:provider), do: gettext("Your conversations with parents will appear here")

  defp empty_state_message(_parent), do: gettext("Your conversations with providers will appear here")

  @doc """
  The provider Comms page frame: full-height page, centred surface column, and the
  sticky header bar that sits above whatever the surface lists.

  Every chrome-shaped thing the provider's own inbox and their read-only view of the
  threads their staff conduct render *identically* lives here (#746). Those two are
  tabs of one surface, so a layout class that drifts between them shows up to the user
  as a jump on tab switch — and a duplicated class is exactly what drifts.

  The `:header` slot is whatever belongs inside the sticky bar: a title plus the tab
  strip on an index, a back link plus a thread title on a thread.

  ## Examples

      <.provider_comms_shell>
        <:header>
          <h1>{gettext("Messages")}</h1>
          <.provider_message_tabs current_tab={:inbox} />
        </:header>
        <.conversation_list ... />
      </.provider_comms_shell>
  """
  slot :header, required: true
  slot :inner_block, required: true

  def provider_comms_shell(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <div class="max-w-2xl mx-auto bg-white min-h-screen shadow-sm">
        <header class="sticky top-0 z-10 bg-white border-b border-gray-200 px-4 py-3">
          {render_slot(@header)}
        </header>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  Renders the conversation index page.

  Uses multi-clause dispatch on `variant` for parent vs provider chrome.
  """
  attr :variant, :atom, required: true, values: [:parent, :provider]
  attr :streams, :any, required: true
  attr :conversations_empty?, :boolean, required: true
  attr :navigate_base, :string, required: true

  slot :tabs,
    doc: """
    Optional strip rendered under the header, above the list. The provider surfaces
    use it to switch between their own inbox and the threads their staff conduct
    (#746); the routes live in the caller so this shared component stays
    persona-agnostic.
    """

  def conversation_index(%{variant: :parent} = assigns) do
    ~H"""
    <div class={["min-h-screen", Theme.bg(:muted)]}>
      <header class={[Theme.gradient(:primary), "px-6 py-4"]}>
        <div class="max-w-2xl mx-auto flex items-center gap-3">
          <.icon name="hero-chat-bubble-left-right" class="w-7 h-7 text-white" />
          <h1 class={[Theme.typography(:section_title), "text-white"]}>
            {gettext("Messages")}
          </h1>
        </div>
      </header>
      <div class="max-w-2xl mx-auto -mt-2">
        <div class={[Theme.bg(:surface), Theme.rounded(:xl), "shadow-sm overflow-hidden"]}>
          <.conversation_list
            streams={@streams}
            conversations_empty?={@conversations_empty?}
            navigate_base={@navigate_base}
            user_type={:parent}
          />
        </div>
      </div>
    </div>
    """
  end

  def conversation_index(%{variant: :provider} = assigns) do
    ~H"""
    <.provider_comms_shell>
      <:header>
        <h1 class={["text-xl font-semibold", Theme.text_color(:heading)]}>
          {gettext("Messages")}
        </h1>
        {render_slot(@tabs)}
      </:header>
      <.conversation_list
        streams={@streams}
        conversations_empty?={@conversations_empty?}
        navigate_base={@navigate_base}
        user_type={:provider}
      />
    </.provider_comms_shell>
    """
  end

  defp conversation_list(assigns) do
    ~H"""
    <div id="conversations" phx-update="stream" class="divide-y divide-hero-grey-200">
      <.conversation_card
        :for={{dom_id, summary} <- @streams.conversations}
        id={dom_id}
        summary={summary}
        user_type={@user_type}
        navigate={@navigate_base <> "/" <> summary.conversation_id}
      />
      <div :if={@conversations_empty?} id="conversations-empty-state" class="p-4">
        <.conversations_empty_state user_type={@user_type} />
      </div>
    </div>
    """
  end

  @doc """
  Renders the conversation show (detail) page.

  Uses multi-clause dispatch on `variant` for parent vs provider chrome.
  """
  attr :variant, :atom, required: true, values: [:parent, :provider]
  attr :streams, :any, required: true
  attr :messages_empty?, :boolean, required: true
  attr :page_title, :string, required: true
  attr :broadcast?, :boolean, default: false
  attr :back_path, :string, required: true
  attr :form, :map, required: true
  attr :current_user_id, :string, required: true
  attr :sender_names, :map, required: true
  attr :provider_user_ids, :any, default: nil
  attr :provider_name, :string, default: nil
  attr :uploads, :any, default: nil

  def conversation_show(%{variant: :parent} = assigns) do
    ~H"""
    <div class={["flex flex-col h-screen", Theme.bg(:muted)]}>
      <div class="max-w-2xl mx-auto w-full flex flex-col h-full">
        <header class={[Theme.gradient(:primary), "px-4 py-3 flex items-center gap-3"]}>
          <.link navigate={@back_path} class="text-white/80 hover:text-white">
            <.icon name="hero-arrow-left" class="w-6 h-6" />
          </.link>
          <div class={[
            "w-10 h-10 rounded-full flex items-center justify-center text-white font-semibold",
            avatar_color(@page_title)
          ]}>
            {String.first(@page_title) |> String.upcase()}
          </div>
          <div class="flex-1">
            <h1 class="text-lg font-semibold text-white truncate">{@page_title}</h1>
            <.broadcast_badge :if={@broadcast?} class="text-white/80" />
          </div>
        </header>
        <div class={[Theme.bg(:surface), "flex-1 flex flex-col shadow-sm overflow-hidden"]}>
          <.message_area
            streams={@streams}
            messages_empty?={@messages_empty?}
            form={@form}
            current_user_id={@current_user_id}
            sender_names={@sender_names}
            broadcast?={@broadcast?}
            provider_user_ids={@provider_user_ids}
            provider_name={@provider_name}
            uploads={@uploads}
            variant={:parent}
          />
        </div>
      </div>
    </div>
    """
  end

  def conversation_show(%{variant: :provider} = assigns) do
    ~H"""
    <div class="flex flex-col h-screen bg-gray-50">
      <div class="max-w-2xl mx-auto w-full flex flex-col h-full bg-white shadow-sm">
        <header class="sticky top-0 z-10 bg-white border-b border-gray-200 px-4 py-3 flex items-center gap-3">
          <.link navigate={@back_path} class="text-gray-500 hover:text-gray-700">
            <.icon name="hero-arrow-left" class="w-6 h-6" />
          </.link>
          <div class="flex-1">
            <h1 class="text-lg font-semibold text-gray-900 truncate">{@page_title}</h1>
            <.broadcast_badge :if={@broadcast?} />
          </div>
        </header>
        <.message_area
          streams={@streams}
          messages_empty?={@messages_empty?}
          form={@form}
          current_user_id={@current_user_id}
          sender_names={@sender_names}
          broadcast?={@broadcast?}
          provider_user_ids={@provider_user_ids}
          provider_name={@provider_name}
          uploads={@uploads}
          variant={:provider}
        />
      </div>
    </div>
    """
  end

  defp message_area(assigns) do
    ~H"""
    <.monitoring_notice />
    <div
      id="messages-container"
      class="flex-1 overflow-y-auto p-4 space-y-3"
      phx-hook="ScrollToBottom"
    >
      <div id="messages" phx-update="stream" class="space-y-3">
        <.message_bubble
          :for={{dom_id, message} <- @streams.messages}
          id={dom_id}
          message={message}
          is_own={MessagingLiveHelper.own_message?(message, @current_user_id)}
          sender_name={MessagingLiveHelper.get_sender_name(@sender_names, message.sender_id)}
          provider_name={@provider_name}
          is_provider_side={MessagingLiveHelper.provider_side?(message, @provider_user_ids)}
        />
      </div>
      <.messages_empty_state :if={@messages_empty?} />
    </div>
    <%= cond do %>
      <% @variant == :provider -> %>
        <.message_input form={@form} uploads={@uploads} />
      <% @broadcast? -> %>
        <.broadcast_reply_bar />
      <% true -> %>
        <.message_input form={@form} uploads={@uploads} />
    <% end %>
    """
  end

  @doc """
  Renders the standing monitoring notice shown at the top of every conversation.

  A banner rather than a `:system` message (#745 allows either). Three reasons: it
  needs no write on any of the four conversation-creation paths, all of which run
  inside a transaction; it covers conversations that already exist, where a
  create-time message would have needed a backfill; and being rendered rather than
  stored, it is undeletable by construction.

  Rendered *above* `#messages-container`, not inside it. Inside, it scrolls away with
  the thread and the `ScrollToBottom` hook lands the reader past it, so on any
  conversation longer than a screen the notice would never be seen — which for a
  disclosure is the same as not having one.

  Every conversation is anchored to a provider — `provider_id` is required on the
  schema — so there is no non-provider conversation to exclude yet. When
  provider-less direct messages exist, gate this on `conversation.provider_id`.

  > The wording is PROVISIONAL and must not ship before legal review (#745).
  """
  def monitoring_notice(assigns) do
    ~H"""
    <div
      id="monitoring-notice"
      data-role="monitoring-notice"
      class={[
        "flex items-start gap-2 px-4 py-2.5 border-b",
        Theme.bg(:light),
        Theme.border_color(:light),
        Theme.text_color(:muted)
      ]}
    >
      <.icon name="hero-information-circle" class="w-4 h-4 shrink-0 mt-0.5" />
      <p class={Theme.typography(:caption)}>
        {gettext(
          "Messages here may be reviewed by the activity provider and by Klass Hero staff, to keep children safe."
        )}
      </p>
    </div>
    """
  end

  @doc """
  Renders the broadcast reply bar shown to parents viewing broadcast conversations.

  Replaces the message input with a note that broadcasts are one-way
  and a button to reply privately to the provider.
  """
  def broadcast_reply_bar(assigns) do
    ~H"""
    <div
      id="broadcast-reply-bar"
      class={["p-4 border-t text-center", Theme.border_color(:light), Theme.bg(:surface)]}
    >
      <p class={["text-sm mb-3", Theme.text_color(:muted)]}>
        {gettext("Broadcast messages are one-way")}
      </p>
      <button
        phx-click="reply_privately"
        class={[
          "inline-flex items-center gap-2 px-6 py-2.5 font-medium transition-colors",
          Theme.button_variant(:primary),
          Theme.rounded(:full)
        ]}
      >
        <.icon name="hero-chat-bubble-left-right" class="w-5 h-5" />
        {gettext("Reply privately")}
      </button>
    </div>
    """
  end

  @avatar_colors {"bg-hero-blue-600", "bg-rose-500", "bg-hero-yellow-500", "bg-emerald-500", "bg-blue-500",
                  "bg-purple-500", "bg-rose-500"}

  @doc "Returns a deterministic Tailwind background color class for a given name."
  def avatar_color(name) do
    index = :erlang.phash2(name, tuple_size(@avatar_colors))
    elem(@avatar_colors, index)
  end

  # Broadcasts have no "other participant" — fallback to "Unknown" was the UX bug in #892.
  defp derive_display_name(%{conversation_type: :program_broadcast, program_name: name})
       when is_binary(name) and byte_size(name) > 0 do
    name
  end

  defp derive_display_name(%{conversation_type: :program_broadcast}) do
    gettext("Program Broadcast")
  end

  defp derive_display_name(%{other_participant_name: name}) when is_binary(name) and byte_size(name) > 0 do
    name
  end

  defp derive_display_name(_summary), do: gettext("Unknown")

  # A row with no message at all still carries whatever latest_message_at the
  # projection last wrote, so the timestamp is gated on the message, not the column.
  #
  # Matched on field names rather than through `ConversationSummary.has_latest_message?/1`,
  # which matches its own struct by name and so would raise on any other row shape.
  # This is the single change that lets the card render a `StaffConversation` too (#746);
  # the schema keeps its own copy for its own callers.
  defp latest_message_timestamp(%{latest_message_content: nil, has_attachments: false}), do: ""

  defp latest_message_timestamp(summary), do: format_timestamp(summary.latest_message_at)

  defp format_timestamp(nil), do: ""

  defp format_timestamp(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> gettext("Now")
      diff < 3600 -> gettext("%{n}m ago", n: div(diff, 60))
      diff < 86_400 -> Calendar.strftime(datetime, "%H:%M")
      diff < 604_800 -> Calendar.strftime(datetime, "%a")
      true -> Calendar.strftime(datetime, "%d %b")
    end
  end

  defp format_message_time(nil), do: ""
  defp format_message_time(datetime), do: Calendar.strftime(datetime, "%H:%M")

  defp preview_content(%{has_attachments: true, latest_message_content: nil}) do
    gettext("Photo")
  end

  defp preview_content(%{has_attachments: true, latest_message_content: content}) when is_binary(content) do
    gettext("Photo") <> " - " <> String.slice(content, 0, 40)
  end

  defp preview_content(%{latest_message_content: content}) when is_binary(content) do
    String.slice(content, 0, 50)
  end

  defp preview_content(_summary), do: gettext("No messages yet")

  defp upload_error_to_string(:too_large) do
    max_mb = div(Attachment.max_file_size_bytes(), 1_048_576)
    gettext("File is too large (max %{mb} MB)", mb: max_mb)
  end

  defp upload_error_to_string(:not_accepted), do: gettext("File type not accepted (images only)")

  defp upload_error_to_string(:too_many_files) do
    max = Attachment.max_per_message()
    gettext("Too many files (max %{max})", max: max)
  end

  defp upload_error_to_string(:external_client_failure), do: gettext("Upload failed")
  defp upload_error_to_string(_), do: gettext("Upload error")

  @doc """
  Renders a "Contact Provider" button that emits a phx-click event
  carrying the program_id and provider_id as phx-values.

  Designed for use inside the `:actions` slot of `<.program_card>`, so the
  card stays purely presentational while the caller owns the event handler.

  ## Examples

      <.contact_provider_button
        program_id={program.id}
        provider_id={program.provider_id}
        phx-click="contact_provider"
      />
  """
  attr :program_id, :string, required: true
  attr :provider_id, :string, required: true
  attr :rest, :global, include: ~w(phx-click disabled)

  def contact_provider_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-value-program-id={@program_id}
      phx-value-provider-id={@provider_id}
      class={[
        "block w-full text-center px-4 py-2 text-sm font-medium",
        Theme.rounded(:lg),
        "bg-hero-blue-50 text-hero-blue-600 hover:bg-hero-blue-100",
        Theme.transition(:normal)
      ]}
      onclick="event.stopPropagation();"
      {@rest}
    >
      <.icon name="hero-chat-bubble-left-right-mini" class="w-4 h-4 inline mr-1" />
      {gettext("Contact Provider")}
    </button>
    """
  end
end
