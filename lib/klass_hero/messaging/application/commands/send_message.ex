defmodule KlassHero.Messaging.Application.Commands.SendMessage do
  @moduledoc """
  Use case for sending a message in a conversation.

  Validates content/attachments, checks participant and broadcast-send permissions,
  uploads files to S3, persists message + attachments (cleaning up S3 on DB failure),
  updates sender's last_read_at, and publishes a message_sent event.
  """

  alias KlassHero.Messaging.Application.Shared
  alias KlassHero.Messaging.Domain.Events.MessagingEvents
  alias KlassHero.Messaging.Domain.Models.Attachment
  alias KlassHero.Messaging.Domain.Models.Message
  alias KlassHero.Repo
  alias KlassHero.Shared.DomainEventBus
  alias KlassHero.Shared.Storage

  require Logger

  @context KlassHero.Messaging
  @conversation_reader Application.compile_env!(:klass_hero, [
                         :messaging,
                         :for_querying_conversations
                       ])
  @message_repo Application.compile_env!(:klass_hero, [:messaging, :for_managing_messages])
  @participant_repo Application.compile_env!(:klass_hero, [:messaging, :for_managing_participants])
  @participant_reader Application.compile_env!(:klass_hero, [:messaging, :for_querying_participants])
  @attachment_repo Application.compile_env!(:klass_hero, [:messaging, :for_managing_attachments])
  @user_resolver Application.compile_env!(:klass_hero, [:messaging, :for_resolving_users])
  @staff_resolver Application.compile_env!(:klass_hero, [:messaging, :for_resolving_program_staff])
  @provider_staff_resolver Application.compile_env!(:klass_hero, [
                             :messaging,
                             :for_resolving_provider_staff
                           ])

  @doc """
  Sends a message to a conversation.

  ## Options
  - `:message_type` — `:text` (default) or `:system`
  - `:conversation` — pre-fetched `%Conversation{}` for the same `conversation_id`
    (skips DB round-trip in broadcast permission check; ignored if ID doesn't match)
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
    trimmed_content = trim_content(content)

    with :ok <- validate_message_content(trimmed_content, attachment_files),
         :ok <- validate_attachment_files(attachment_files),
         :ok <- Shared.verify_participant(conversation_id, sender_id, @participant_reader),
         :ok <- verify_broadcast_send_permission(conversation_id, sender_id, conversation),
         {:ok, uploaded_files} <- upload_files(attachment_files, conversation_id),
         {:ok, message_with_attachments} <-
           persist_message_and_attachments(
             conversation_id,
             sender_id,
             trimmed_content,
             message_type,
             uploaded_files
           ) do
      update_sender_read_status(conversation_id, sender_id)
      publish_event(message_with_attachments)

      Logger.info("Message sent",
        message_id: message_with_attachments.id,
        conversation_id: conversation_id,
        sender_id: sender_id
      )

      {:ok, message_with_attachments}
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

  defp persist_message_and_attachments(conversation_id, sender_id, content, message_type, uploaded_files) do
    message_attrs = %{
      conversation_id: conversation_id,
      sender_id: sender_id,
      content: content,
      message_type: message_type
    }

    result =
      Repo.transaction(fn ->
        with {:ok, message} <- @message_repo.create(message_attrs),
             {:ok, attachments} <- create_attachments(message.id, uploaded_files) do
          %{message | attachments: attachments}
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, message_with_attachments} ->
        {:ok, message_with_attachments}

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

    @attachment_repo.create_many(attrs_list)
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

  # Broadcast conversations are one-way: only the provider owner and assigned staff may send.
  # Parents replying would expose messages to all other participants (privacy breach).
  defp verify_broadcast_send_permission(conversation_id, sender_id, conversation) do
    # Validates conversation.id matches conversation_id to prevent a mismatched
    # pre-fetched struct from bypassing broadcast guards.
    result =
      if conversation && conversation.id == conversation_id,
        do: {:ok, conversation},
        else: @conversation_reader.get_by_id(conversation_id)

    case result do
      {:ok, %{type: :program_broadcast, provider_id: provider_id, program_id: program_id}} ->
        check_broadcast_reply_permission(provider_id, program_id, sender_id)

      {:ok, _direct_conversation} ->
        :ok

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  defp check_broadcast_reply_permission(provider_id, program_id, sender_id) do
    cond do
      provider_owner?(provider_id, sender_id) -> :ok
      staff_assigned?(program_id, sender_id) -> :ok
      active_staff_for_provider?(provider_id, sender_id) -> :ok
      true -> {:error, :broadcast_reply_not_allowed}
    end
  end

  defp provider_owner?(provider_id, sender_id) do
    case @user_resolver.get_user_id_for_provider(provider_id) do
      {:ok, ^sender_id} -> true
      _ -> false
    end
  end

  defp staff_assigned?(nil, _sender_id), do: false

  defp staff_assigned?(program_id, sender_id) do
    staff_user_ids = @staff_resolver.get_active_staff_user_ids(program_id)
    sender_id in staff_user_ids
  end

  # `program_staff_participants` projection covers only explicit program assignments;
  # provider-level staff are also authorised to broadcast for any program of their
  # provider (see `StaffBroadcastLive.mount/3`). The two checks must agree — bug #669.
  defp active_staff_for_provider?(provider_id, sender_id) do
    @provider_staff_resolver.active_staff_for_provider?(provider_id, sender_id)
  end

  defp update_sender_read_status(conversation_id, sender_id) do
    now = DateTime.utc_now()

    case @participant_repo.mark_as_read(conversation_id, sender_id, now) do
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

  defp publish_event(message) do
    event =
      MessagingEvents.message_sent(
        message.conversation_id,
        message.id,
        message.sender_id,
        message.content,
        message.message_type,
        message.inserted_at,
        message.attachments
      )

    DomainEventBus.dispatch(@context, event)
    :ok
  end
end
