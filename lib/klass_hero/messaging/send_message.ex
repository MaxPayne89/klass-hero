defmodule KlassHero.Messaging.SendMessage do
  @moduledoc """
  Use case for sending a message in a conversation.

  Validates content/attachments, resolves the sender's role relative to the
  conversation's provider (which both authorizes the send and is recorded on the
  message), uploads files to S3, persists message + attachments (cleaning up S3 on
  DB failure), updates sender's last_read_at, and publishes a message_sent event.
  """

  use KlassHero.Shared.Tracing

  alias KlassHero.Messaging.Attachment
  alias KlassHero.Messaging.Domain.Events.MessagingEvents
  alias KlassHero.Messaging.Message
  alias KlassHero.Messaging.Notifications
  alias KlassHero.Messaging.Shared
  alias KlassHero.Shared.Outbox
  alias KlassHero.Shared.Storage

  require Logger

  @context KlassHero.Messaging

  @doc """
  Sends a message to a conversation.

  ## Options
  - `:message_type` — `:text` (default) or `:system`
  - `:conversation` — pre-fetched `%Conversation{}` for the same `conversation_id`
    (skips the DB round-trip taken to authorize; ignored if ID doesn't match)
  - `:attachments` — list of `%{binary: <<>>, filename: "x.jpg", content_type: "image/jpeg", size: 1000}`

  ## Returns
  - `{:ok, message}` — message sent (attachments populated)
  - `{:error, :empty_message | :too_many_attachments | :invalid_attachment_type | :attachment_too_large | :not_participant | :broadcast_reply_not_allowed | term()}`
  """
  @spec execute(String.t(), String.t(), String.t() | nil, keyword()) ::
          {:ok, Message.t()}
          | {:error,
             :empty_message
             | :too_many_attachments
             | :invalid_attachment_type
             | :attachment_too_large
             | :upload_failed
             | :not_participant
             | :broadcast_reply_not_allowed
             | term()}
  def execute(conversation_id, sender_id, content, opts \\ []) do
    message_type = Keyword.get(opts, :message_type, :text)
    conversation = Keyword.get(opts, :conversation)
    attachment_files = Keyword.get(opts, :attachments, [])

    with {:ok, trimmed_content} <- validate_content(content, attachment_files),
         :ok <- validate_attachment_files(attachment_files),
         :ok <- Shared.verify_participant(conversation_id, sender_id),
         {:ok, loaded_conversation} <- load_conversation(conversation_id, conversation),
         {:ok, sender_role} <- authorize_sender(loaded_conversation, sender_id),
         {:ok, uploaded_files} <- upload_files(attachment_files, conversation_id),
         {:ok, message_with_attachments} <-
           persist_message_and_attachments(
             conversation_id,
             sender_id,
             sender_role,
             trimmed_content,
             message_type,
             uploaded_files
           ) do
      update_sender_read_status(conversation_id, sender_id)
      Notifications.message_sent(conversation_id, message_with_attachments.id)

      Logger.info("Message sent",
        message_id: message_with_attachments.id,
        conversation_id: conversation_id,
        sender_id: sender_id
      )

      {:ok, message_with_attachments}
    end
  end

  @doc """
  Trims `content` and checks the message carries something to send.

  Public so `StartConversationWithMessage` can apply the rule *before* creating a
  conversation — creating one for a message about to be rejected is #1446.
  """
  @spec validate_content(String.t() | nil, list()) ::
          {:ok, String.t() | nil} | {:error, :empty_message}
  def validate_content(content, attachment_files) do
    trimmed = trim_content(content)

    case validate_message_content(trimmed, attachment_files) do
      :ok -> {:ok, trimmed}
      error -> error
    end
  end

  defp trim_content(content) when is_binary(content), do: String.trim(content)
  defp trim_content(nil), do: nil

  defp validate_message_content(nil, []), do: {:error, :empty_message}
  defp validate_message_content("", []), do: {:error, :empty_message}
  defp validate_message_content(_content, _attachments), do: :ok

  defp validate_attachment_files([]), do: :ok

  defp validate_attachment_files(files) do
    cond do
      length(files) > Attachment.max_per_message() ->
        {:error, :too_many_attachments}

      Enum.any?(files, fn f -> f.content_type not in Attachment.allowed_content_types() end) ->
        {:error, :invalid_attachment_type}

      Enum.any?(files, fn f -> f.size > Attachment.max_file_size_bytes() end) ->
        {:error, :attachment_too_large}

      true ->
        :ok
    end
  end

  defp upload_files([], _conversation_id), do: {:ok, []}

  defp upload_files(files, conversation_id) do
    results =
      files
      |> Task.async_stream(
        fn file ->
          ext = Path.extname(file.filename)
          uuid = Ecto.UUID.generate()
          path = "messaging/attachments/#{conversation_id}/#{uuid}#{ext}"

          case Storage.upload(:public, path, file.binary, content_type: file.content_type) do
            {:ok, url} ->
              {:ok,
               %{
                 file_url: url,
                 storage_path: path,
                 original_filename: sanitize_filename(file.filename),
                 content_type: file.content_type,
                 file_size_bytes: file.size
               }}

            {:error, reason} ->
              {:error, reason}
          end
        end,
        timeout: :infinity
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> {:error, {:task_crashed, reason}}
      end)

    {successes, failures} = Enum.split_with(results, &match?({:ok, _}, &1))

    case failures do
      [] ->
        {:ok, Enum.map(successes, fn {:ok, uploaded} -> uploaded end)}

      [{:error, reason} | _] ->
        uploaded = Enum.map(successes, fn {:ok, uploaded} -> uploaded end)
        cleanup_uploaded_files(uploaded)

        Logger.error("Failed to upload attachment",
          conversation_id: conversation_id,
          reason: inspect(reason)
        )

        {:error, :upload_failed}
    end
  end

  defp persist_message_and_attachments(conversation_id, sender_id, sender_role, content, message_type, uploaded_files) do
    message_attrs = %{
      conversation_id: conversation_id,
      sender_id: sender_id,
      sender_role: sender_role,
      content: content,
      message_type: message_type
    }

    result =
      Outbox.transact(@context, fn ->
        with {:ok, message} <- KlassHero.Messaging.create_message(message_attrs),
             {:ok, attachments} <- create_attachments(message.id, uploaded_files) do
          message = %{message | attachments: attachments}
          {:ok, message, [message_sent_event(message)]}
        end
      end)

    case result do
      {:ok, _message} = ok ->
        ok

      {:error, reason} ->
        cleanup_uploaded_files(uploaded_files)

        Logger.error("Failed to persist message with attachments, cleaning up S3 files",
          conversation_id: conversation_id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp create_attachments(_message_id, []), do: {:ok, []}

  defp create_attachments(message_id, uploaded_files) do
    attrs_list =
      Enum.map(uploaded_files, fn file ->
        Map.put(file, :message_id, message_id)
      end)

    KlassHero.Messaging.create_attachments(attrs_list)
  end

  defp cleanup_uploaded_files([]), do: :ok

  defp cleanup_uploaded_files(uploaded_files) do
    Enum.each(uploaded_files, fn file ->
      case Storage.delete(:public, file.storage_path) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning("Failed to clean up S3 file",
            storage_path: file.storage_path,
            reason: inspect(reason)
          )
      end
    end)
  end

  defp sanitize_filename(filename) do
    filename
    |> Path.basename()
    |> String.replace(~r/[^\w\s\-.]/, "")
    |> String.slice(0, 255)
  end

  # Validates conversation.id matches conversation_id to prevent a mismatched
  # pre-fetched struct from bypassing the broadcast guard below.
  defp load_conversation(conversation_id, prefetched) do
    if prefetched && prefetched.id == conversation_id,
      do: {:ok, prefetched},
      else: KlassHero.Messaging.get_conversation_by_id(conversation_id)
  end

  # Resolves the sender's role once and authorizes from it, so attribution and
  # permission can never disagree. They used to be separate computations over
  # different staff sets — provider-wide here, program-scoped in the renderer —
  # which is how an unassigned staff member came to be allowed to send a message
  # that rendered as if a parent had sent it (#1348).
  #
  # Broadcast conversations are one-way: only the provider owner and their
  # currently employed staff may send. Parents replying would expose messages to
  # all other participants (privacy breach).
  defp authorize_sender(conversation, sender_id) do
    case {conversation.type, resolve_sender_role(conversation.provider_id, sender_id)} do
      {:program_broadcast, :parent} -> {:error, :broadcast_reply_not_allowed}
      {_type, role} -> {:ok, role}
    end
  end

  defp resolve_sender_role(provider_id, sender_id) do
    cond do
      provider_owner?(provider_id, sender_id) -> :provider
      active_staff_for_provider?(provider_id, sender_id) -> :staff
      true -> :parent
    end
  end

  defp provider_owner?(provider_id, sender_id) do
    owner =
      acl_span source: "messaging", target: "provider" do
        KlassHero.Provider.get_identity_id_for_provider(provider_id)
      end

    match?({:ok, ^sender_id}, owner)
  end

  # Current employment at the provider is the whole authorization fact — staff may
  # follow up on any program of their provider (bug #669), so a per-program check
  # against `program_staff_participants` would only ever narrow this for people the
  # mirror has drifted on. That is exactly what it did: the mirror is never told
  # about deactivation (#1237) or hard removal (#1292), so it kept authorizing both
  # (#1320). Deriving from `staff_members.active` also means reactivation restores
  # access with no event, replay, or backfill.
  defp active_staff_for_provider?(provider_id, sender_id) do
    acl_span source: "messaging", target: "provider" do
      KlassHero.Provider.active_staff_for_provider?(provider_id, sender_id)
    end
  end

  defp update_sender_read_status(conversation_id, sender_id) do
    now = DateTime.utc_now()

    case KlassHero.Messaging.mark_participant_read(conversation_id, sender_id, now) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to update sender read status",
          conversation_id: conversation_id,
          sender_id: sender_id,
          reason: inspect(reason)
        )

        :ok
    end
  end

  defp message_sent_event(message) do
    MessagingEvents.message_sent(
      message.conversation_id,
      message.id,
      message.sender_id,
      message.content,
      message.message_type,
      message.inserted_at,
      message.attachments
    )
  end
end
