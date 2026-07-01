defmodule KlassHeroWeb.MessagingLiveHelper do
  @moduledoc """
  Shared helper module for messaging LiveViews.

  LiveViews `use` this module with a view type to inject shared callbacks:

      use KlassHeroWeb.MessagingLiveHelper, :show   # conversation detail callbacks
      use KlassHeroWeb.MessagingLiveHelper, :index   # conversation list callbacks

  Each LiveView only needs to implement `mount/3` and `render/1`.
  """

  use Gettext, backend: KlassHeroWeb.Gettext

  use Phoenix.VerifiedRoutes,
    endpoint: KlassHeroWeb.Endpoint,
    router: KlassHeroWeb.Router,
    statics: KlassHeroWeb.static_paths()

  import Phoenix.Component, only: [assign: 3]

  import Phoenix.LiveView,
    only: [
      allow_upload: 3,
      cancel_upload: 3,
      connected?: 1,
      consume_uploaded_entries: 3,
      push_event: 3,
      put_flash: 3,
      push_navigate: 2,
      stream: 3,
      stream: 4,
      stream_insert: 4
    ]

  alias KlassHero.Messaging
  alias KlassHero.Messaging.Attachment
  alias KlassHero.Messaging.Domain.Models.Message
  alias KlassHero.Shared.Domain.Events.DomainEvent
  alias Phoenix.LiveView.Socket

  require Logger

  @doc false
  defmacro __using__(:show) do
    quote do
      alias KlassHero.Shared.Domain.Events.DomainEvent
      alias KlassHeroWeb.MessagingLiveHelper

      require Logger

      @impl true
      def handle_event("send_message", params, socket) do
        MessagingLiveHelper.handle_send_message(params, socket)
      end

      @impl true
      def handle_info({:domain_event, %DomainEvent{event_type: :message_sent} = event}, socket) do
        MessagingLiveHelper.handle_message_sent_event(event, socket)
      end

      @impl true
      def handle_info({:domain_event, %DomainEvent{event_type: :messages_read} = event}, socket) do
        Logger.debug("Messages read by user", user_id: event.payload.user_id)
        {:noreply, socket}
      end

      @impl true
      def handle_event("validate", _params, socket) do
        {:noreply, socket}
      end

      @impl true
      def handle_event("cancel-upload", %{"ref" => ref}, socket) do
        {:noreply, MessagingLiveHelper.cancel_attachment_upload(socket, ref)}
      end

      @impl true
      def handle_event("reply_privately", _params, socket) do
        MessagingLiveHelper.handle_reply_privately(socket)
      end
    end
  end

  defmacro __using__(:index) do
    quote do
      alias KlassHero.Shared.Domain.Events.DomainEvent
      alias KlassHeroWeb.MessagingLiveHelper

      @impl true
      def handle_info({:domain_event, %DomainEvent{event_type: :message_sent}}, socket) do
        MessagingLiveHelper.refresh_conversations(socket)
      end

      @impl true
      def handle_info({:domain_event, %DomainEvent{event_type: :conversation_created}}, socket) do
        MessagingLiveHelper.refresh_conversations(socket)
      end
    end
  end

  @doc """
  Trims a broadcast's subject/content and consumes attachment uploads.

  Returns `{:ok, subject, content, attachments}` or `:empty` when trimmed content
  and attachment list are both blank. Shared by provider and staff broadcast composers.
  """
  @spec consume_and_validate_broadcast(Socket.t(), map()) ::
          {:ok, String.t(), String.t(), list()} | :empty
  def consume_and_validate_broadcast(socket, %{"subject" => subject, "content" => content}) do
    content = String.trim(content)
    subject = String.trim(subject)
    attachments = consume_attachment_uploads(socket)

    if content == "" and attachments == [] do
      :empty
    else
      {:ok, subject, content, attachments}
    end
  end

  @doc """
  Mounts a conversation show view.

  Options: `:back_path` (required), `:variant` (`:parent`/`:provider`/`:staff`, default `:parent`).
  The `:variant` controls whether the page title includes the enrolled-child suffix.
  """

  def mount_conversation_show(socket, conversation_id, opts) do
    back_path = Keyword.fetch!(opts, :back_path)
    variant = Keyword.get(opts, :variant, :parent)
    user_id = socket.assigns.current_scope.user.id
    mark_as_read? = connected?(socket)

    case Messaging.get_conversation(conversation_id, user_id, mark_as_read: mark_as_read?) do
      {:ok,
       %{
         conversation: conversation,
         messages: messages,
         has_more: has_more,
         sender_names: sender_names
       }} ->
        if connected?(socket), do: subscribe_to_conversation(conversation_id)

        reversed_messages = Enum.reverse(messages)

        {provider_user_ids, provider_name} = resolve_provider_info(conversation)

        socket =
          socket
          |> assign(:page_title, build_page_title(conversation, user_id, variant))
          |> assign(:conversation, conversation)
          |> assign(:has_more, has_more)
          |> assign(:messages_empty?, Enum.empty?(messages))
          |> assign(:sender_names, sender_names)
          |> assign(:provider_user_ids, provider_user_ids)
          |> assign(:provider_name, provider_name)
          |> assign(:form, Phoenix.Component.to_form(%{"content" => ""}))
          |> assign(:back_path, back_path)
          |> allow_upload(:attachments,
            accept: ~w(.jpg .jpeg .png .gif .webp),
            max_entries: 5,
            max_file_size: 10_485_760
          )
          |> stream(:messages, reversed_messages)

        {:ok, socket}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Conversation not found"))
         |> push_navigate(to: back_path)}

      {:error, :not_participant} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("You don't have access to this conversation"))
         |> push_navigate(to: back_path)}
    end
  end

  @doc """
  Handles the send_message event. Consumes pending uploads and sends with optional attachments.
  """
  def handle_send_message(%{"content" => content}, socket) do
    content = String.trim(content)
    file_data = consume_attachment_uploads(socket)
    has_attachments = file_data != []

    if content == "" and not has_attachments do
      {:noreply, socket}
    else
      conversation_id = socket.assigns.conversation.id
      sender_id = socket.assigns.current_scope.user.id
      message_content = if content != "", do: content

      opts = [
        conversation: socket.assigns.conversation,
        attachments: file_data
      ]

      case Messaging.send_message(conversation_id, sender_id, message_content, opts) do
        {:ok, _message} ->
          {:noreply,
           socket
           |> assign(:form, Phoenix.Component.to_form(%{"content" => ""}))
           |> push_event("clear_message_input", %{})}

        {:error, reason} ->
          Logger.error("Failed to send message", reason: reason)
          {:noreply, put_flash(socket, :error, upload_error_message(reason))}
      end
    end
  end

  @doc """
  Handles the reply_privately event for broadcast conversations.
  """
  def handle_reply_privately(socket) do
    conversation = socket.assigns.conversation

    # Handler is injected into all show LiveViews; UI hides the button, but crafted events could bypass it.
    if conversation.type == :program_broadcast do
      scope = socket.assigns.current_scope
      back_path = socket.assigns.back_path

      case Messaging.reply_privately_to_broadcast(scope, conversation.id) do
        {:ok, direct_conversation_id} ->
          direct_path = reply_privately_path(back_path, direct_conversation_id)
          {:noreply, push_navigate(socket, to: direct_path)}

        {:error, reason} ->
          Logger.error("Failed to create private reply",
            conversation_id: conversation.id,
            reason: inspect(reason)
          )

          {:noreply, put_flash(socket, :error, gettext("Could not start private conversation"))}
      end
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         gettext("Reply privately is only available for broadcast messages")
       )}
    end
  end

  @doc """
  Handles incoming message_sent domain events; updates sender names if needed.
  """
  def handle_message_sent_event(%DomainEvent{payload: payload} = _event, socket) do
    if payload.conversation_id == socket.assigns.conversation.id do
      user_id = socket.assigns.current_scope.user.id
      Messaging.mark_as_read(payload.conversation_id, user_id)

      sender_names = socket.assigns.sender_names
      sender_name = Map.get(sender_names, payload.sender_id)

      socket =
        if sender_name do
          socket
        else
          update_sender_names_for_new_message(socket, payload.sender_id)
        end

      message = build_message_from_event(payload)

      socket =
        socket
        |> assign(:messages_empty?, false)
        |> stream_insert(:messages, message, at: -1)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @doc """
  Mounts a conversation index view. Option: `:navigate_base` (required).
  """
  def mount_conversation_index(socket, opts) do
    navigate_base = Keyword.fetch!(opts, :navigate_base)
    user_id = socket.assigns.current_scope.user.id

    if connected?(socket), do: subscribe_to_user_updates(user_id)

    {:ok, conversations, _has_more} = Messaging.list_conversations(user_id)

    socket =
      socket
      |> assign(:page_title, gettext("Messages"))
      |> assign(:navigate_base, navigate_base)
      |> assign(:conversations_empty?, Enum.empty?(conversations))
      |> Phoenix.LiveView.stream_configure(:conversations,
        dom_id: &"conversations-#{&1.conversation.id}"
      )
      |> stream(:conversations, conversations)

    {:ok, socket}
  end

  def refresh_conversations(socket) do
    user_id = socket.assigns.current_scope.user.id
    {:ok, conversations, _has_more} = Messaging.list_conversations(user_id)

    socket =
      socket
      |> assign(:conversations_empty?, Enum.empty?(conversations))
      |> stream(:conversations, conversations, reset: true)

    {:noreply, socket}
  end

  @doc """
  Returns the title for a conversation.
  For provider view with enrolled children: "Sarah Johnson for Emma, Liam".
  """
  def get_conversation_title(conversation, enrolled_child_names \\ [], other_participant_name \\ nil)

  def get_conversation_title(%{type: :direct}, child_names, other_name)
      when child_names != [] and not is_nil(other_name) do
    formatted = Enum.join(child_names, ", ")
    "#{other_name} #{gettext("for")} #{formatted}"
  end

  def get_conversation_title(%{type: :direct}, _child_names, other_name) when not is_nil(other_name) do
    other_name
  end

  def get_conversation_title(%{type: :program_broadcast, subject: subject}, _, _) when not is_nil(subject) do
    subject
  end

  def get_conversation_title(%{type: :program_broadcast}, _, _) do
    gettext("Program Broadcast")
  end

  def get_conversation_title(_conversation, _, _) do
    gettext("Conversation")
  end

  def own_message?(message, user_id) do
    message.sender_id == user_id
  end

  def get_sender_name(sender_names, sender_id) do
    Map.get(sender_names, sender_id, "Unknown")
  end

  # Parents know their own children — suppress the "for {names}" suffix for them; show for provider/staff.
  defp build_page_title(conversation, user_id, variant) do
    context = fetch_conversation_context(conversation.id, user_id)
    child_names = enrolled_child_names_for(variant, context.enrolled_child_names)
    get_conversation_title(conversation, child_names, context.other_participant_name)
  end

  @doc false
  def enrolled_child_names_for(:parent, _names), do: []
  def enrolled_child_names_for(_variant, names), do: names

  defp fetch_conversation_context(conversation_id, user_id) do
    Messaging.get_conversation_context(conversation_id, user_id)
  end

  # Single fetch avoids separate round-trips for identity_id and business_name.
  defp resolve_provider_info(conversation) do
    staff_ids =
      if conversation.program_id do
        Messaging.get_active_staff_user_ids(conversation.program_id)
      else
        []
      end

    case KlassHero.Provider.get_provider_profile(conversation.provider_id) do
      {:ok, provider} ->
        {MapSet.new([provider.identity_id | staff_ids]), provider.business_name}

      _ ->
        {MapSet.new(staff_ids), nil}
    end
  end

  defp build_message_from_event(payload) do
    attachments = build_attachments_from_event(payload.message_id, Map.get(payload, :attachments, []))

    %Message{
      id: payload.message_id,
      conversation_id: payload.conversation_id,
      sender_id: payload.sender_id,
      content: payload.content,
      message_type: payload.message_type,
      inserted_at: payload.sent_at,
      attachments: attachments
    }
  end

  defp build_attachments_from_event(message_id, attachments) when is_list(attachments) do
    Enum.map(attachments, fn att ->
      %Attachment{
        id: att.id,
        message_id: message_id,
        file_url: att.file_url,
        original_filename: att.original_filename,
        content_type: att.content_type,
        file_size_bytes: att.file_size_bytes
      }
    end)
  end

  defp build_attachments_from_event(_message_id, other) do
    Logger.warning("Unexpected attachments format in event payload",
      received: inspect(other)
    )

    []
  end

  defp update_sender_names_for_new_message(socket, sender_id) do
    case Messaging.get_display_name(sender_id) do
      {:ok, name} ->
        sender_names = Map.put(socket.assigns.sender_names, sender_id, name)
        assign(socket, :sender_names, sender_names)

      {:error, :not_found} ->
        socket
    end
  end

  defp reply_privately_path("/provider/messages", conversation_id), do: ~p"/provider/messages/#{conversation_id}"

  defp reply_privately_path(_back_path, conversation_id), do: ~p"/messages/#{conversation_id}"

  def cancel_attachment_upload(socket, ref) do
    cancel_upload(socket, :attachments, ref)
  end

  @doc """
  Consumes pending `:attachments` uploads, reads each file into memory, and returns
  a list of `%{binary, filename, content_type, size}` maps. Failed reads are logged and dropped.
  """
  def consume_attachment_uploads(socket) do
    results =
      consume_uploaded_entries(socket, :attachments, fn %{path: path}, entry ->
        case File.read(path) do
          {:ok, binary} ->
            {:ok,
             %{
               binary: binary,
               filename: entry.client_name,
               content_type: entry.client_type,
               size: entry.client_size
             }}

          {:error, reason} ->
            Logger.error("Failed to read uploaded file",
              filename: entry.client_name,
              reason: inspect(reason)
            )

            {:ok, nil}
        end
      end)

    Enum.reject(results, &is_nil/1)
  end

  def upload_error_message(:empty_message), do: gettext("Please enter a message or attach a photo.")

  def upload_error_message(:too_many_attachments),
    do: gettext("Too many files (max %{max}).", max: Attachment.max_per_message())

  def upload_error_message(:invalid_attachment_type), do: gettext("Only images are accepted (JPG, PNG, GIF, WebP).")

  def upload_error_message(:attachment_too_large),
    do: gettext("File is too large (max %{mb} MB).", mb: div(Attachment.max_file_size_bytes(), 1_048_576))

  def upload_error_message(:upload_failed), do: gettext("Failed to upload files. Please try again.")
  def upload_error_message(_), do: gettext("Something went wrong. Please try again.")

  defp subscribe_to_conversation(conversation_id) do
    topic = Messaging.conversation_topic(conversation_id)
    Phoenix.PubSub.subscribe(KlassHero.PubSub, topic)
  end

  defp subscribe_to_user_updates(user_id) do
    topic = Messaging.user_messages_topic(user_id)
    Phoenix.PubSub.subscribe(KlassHero.PubSub, topic)
  end
end
