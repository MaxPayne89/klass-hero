defmodule KlassHero.Messaging.Application.Commands.BroadcastToProgram do
  @moduledoc """
  Use case for sending a broadcast message to all enrolled parents of a program.

  This use case:
  1. Checks if the provider can send broadcasts (entitlement check)
  2. Creates or retrieves the program broadcast conversation
  3. Adds all enrolled parents (and assigned staff) as participants
  4. Delegates message creation to `SendMessage`, which handles validation,
     attachment uploads, transactional persistence, and `:message_sent` event
     publication
  """

  alias KlassHero.Accounts.Scope
  alias KlassHero.Messaging.Application.Commands.AddAssignedStaff
  alias KlassHero.Messaging.Application.Commands.SendMessage
  alias KlassHero.Messaging.Application.Shared
  alias KlassHero.Messaging.Domain.Models.Conversation
  alias KlassHero.Messaging.Domain.Models.Message
  alias KlassHero.Repo
  alias KlassHero.Shared.EventDispatchHelper

  require Logger

  @context KlassHero.Messaging

  @conversation_repo Application.compile_env!(:klass_hero, [
                       :messaging,
                       :for_managing_conversations
                     ])
  @conversation_reader Application.compile_env!(:klass_hero, [
                         :messaging,
                         :for_querying_conversations
                       ])
  @enrollment_resolver Application.compile_env!(:klass_hero, [
                         :messaging,
                         :for_querying_enrollments
                       ])
  @participant_repo Application.compile_env!(:klass_hero, [:messaging, :for_managing_participants])

  @doc """
  Sends a broadcast message to all enrolled parents of a program.

  ## Parameters
  - scope: The provider's scope (for entitlement checks)
  - program_id: The program to broadcast to
  - content: The message content
  - opts: Optional parameters
    - subject: Subject line for the broadcast
    - attachments: List of `%{binary, filename, content_type, size}` maps,
      forwarded verbatim to `SendMessage`
    - provider_id: Explicit provider ID (defaults to scope.provider.id).
      Required when scope.provider is nil (e.g. staff member scopes).
    - skip_entitlement_check: When true, skips the entitlement check.
      Caller is responsible for verifying entitlements before calling.

  ## Returns
  - `{:ok, conversation, message, recipient_count}` - Broadcast sent
  - `{:error, :not_entitled}` - Provider cannot send broadcasts
  - `{:error, :no_enrollments}` - No enrolled parents to broadcast to
  - `{:error, :missing_provider_id}` - Could not resolve a provider_id
  - `{:error, reason}` - Errors surfaced from `SendMessage` (validation, upload, persistence)
  """
  @spec execute(Scope.t(), String.t(), String.t(), keyword()) ::
          {:ok, Conversation.t(), Message.t(), non_neg_integer()}
          | {:error,
             :not_entitled
             | :no_enrollments
             | :missing_provider_id
             | :empty_message
             | :too_many_attachments
             | :invalid_attachment_type
             | :attachment_too_large
             | :upload_failed
             | :not_participant
             | :broadcast_reply_not_allowed
             | term()}
  def execute(%Scope{} = scope, program_id, content, opts \\ []) do
    provider_id = Keyword.get(opts, :provider_id) || (scope.provider && scope.provider.id)

    if is_nil(provider_id) do
      Logger.error("BroadcastToProgram called without provider_id",
        user_id: scope.user.id,
        program_id: program_id
      )

      {:error, :missing_provider_id}
    else
      execute_broadcast(scope, program_id, content, provider_id, opts)
    end
  end

  defp execute_broadcast(scope, program_id, content, provider_id, opts) do
    subject = Keyword.get(opts, :subject)
    attachments = Keyword.get(opts, :attachments, [])
    # Trigger: attachment-only broadcast composer submits an empty content string
    # Why: SendMessage.trim_content/1 preserves "", so the persisted message would
    #      carry content: "" while attachment-only direct messages carry content: nil
    # Outcome: attachment-only broadcasts match direct-message behaviour
    normalized_content = normalize_content(content, attachments)

    with :ok <- Shared.maybe_check_entitlement(scope, opts, provider_id: provider_id),
         {:ok, parent_user_ids} <- get_enrolled_parent_user_ids(program_id),
         :ok <- verify_has_recipients(parent_user_ids),
         {:ok, conversation} <- get_or_create_broadcast_conversation(provider_id, program_id, subject),
         :ok <- setup_participants(conversation, scope, parent_user_ids),
         {:ok, message} <-
           SendMessage.execute(conversation.id, scope.user.id, normalized_content,
             conversation: conversation,
             attachments: attachments
           ) do
      recipient_count = length(parent_user_ids)

      Logger.info("Broadcast sent to program",
        program_id: program_id,
        conversation_id: conversation.id,
        recipient_count: recipient_count
      )

      {:ok, conversation, message, recipient_count}
    end
  end

  defp get_enrolled_parent_user_ids(program_id) do
    {:ok, @enrollment_resolver.get_enrolled_parent_user_ids(program_id)}
  end

  defp verify_has_recipients([]), do: {:error, :no_enrollments}
  defp verify_has_recipients(_), do: :ok

  defp normalize_content(nil, _attachments), do: nil

  defp normalize_content(content, attachments) when is_binary(content) do
    case {String.trim(content), attachments} do
      {"", [_ | _]} -> nil
      {trimmed, _} -> trimmed
    end
  end

  # Trigger: broadcast participants need to be present before SendMessage runs
  # Why: SendMessage.verify_participant rejects senders not in the conversation —
  #      provider/staff sender must be added before delegation. AddAssignedStaff
  #      now returns its :participant_added domain event as data; dispatch
  #      happens after the transaction commits so the projection on a separate
  #      DB connection can read-your-own-writes.
  # Outcome: parents, sender, and assigned staff added in a single transaction;
  #          on commit, all collected events fan out via EventDispatchHelper.
  defp setup_participants(conversation, scope, parent_user_ids) do
    Repo.transaction(fn ->
      with {:ok, _} <- @participant_repo.add_batch(conversation.id, parent_user_ids),
           {:ok, _} <-
             @participant_repo.add_or_get(%{
               conversation_id: conversation.id,
               user_id: scope.user.id
             }),
           {:ok, {_staff_ids, staff_events}} <-
             AddAssignedStaff.execute(conversation.id, conversation.program_id, scope.user.id) do
        staff_events
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, events} ->
        Enum.each(events, &EventDispatchHelper.dispatch(&1, @context))
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_or_create_broadcast_conversation(provider_id, program_id, subject) do
    # Trigger: check for existing broadcast BEFORE attempting insert
    # Why: avoids unique constraint violation that would abort a parent transaction
    # Outcome: existing conversation reused; new one created only if none exists
    case @conversation_reader.find_active_broadcast_for_program(provider_id, program_id) do
      {:ok, conversation} ->
        {:ok, conversation}

      {:error, :not_found} ->
        attrs = %{
          type: :program_broadcast,
          provider_id: provider_id,
          program_id: program_id,
          subject: subject
        }

        case @conversation_repo.create(attrs) do
          {:ok, conversation} ->
            {:ok, conversation}

          # Trigger: race condition — another request created the conversation between
          #          our find and our create
          # Why: unique constraint fires; handle gracefully by re-querying
          # Outcome: return the conversation that won the race
          {:error, :duplicate_broadcast} ->
            @conversation_reader.find_active_broadcast_for_program(provider_id, program_id)
        end
    end
  end
end
