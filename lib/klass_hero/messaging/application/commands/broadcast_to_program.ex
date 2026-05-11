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
  alias KlassHero.Messaging.Application.Commands.SendMessage
  alias KlassHero.Messaging.Application.Shared
  alias KlassHero.Messaging.Domain.Models.Conversation
  alias KlassHero.Messaging.Domain.Models.Message

  require Logger

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

    with :ok <- Shared.maybe_check_entitlement(scope, opts, provider_id: provider_id),
         {:ok, parent_user_ids} <- get_enrolled_parent_user_ids(program_id),
         :ok <- verify_has_recipients(parent_user_ids),
         {:ok, conversation} <- get_or_create_broadcast_conversation(provider_id, program_id, subject),
         :ok <- setup_participants(conversation, scope, parent_user_ids),
         {:ok, message} <-
           SendMessage.execute(conversation.id, scope.user.id, content,
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

  # Trigger: broadcast participants need to be present before SendMessage runs
  # Why: SendMessage.verify_participant rejects senders not in the conversation —
  #      provider/staff sender must be added before delegation
  # Outcome: parents, sender, and assigned staff are participants; partial failure
  #          is recoverable via idempotent retry (add_batch, add_or_get, projection
  #          lookup all heal on re-run)
  defp setup_participants(conversation, scope, parent_user_ids) do
    with {:ok, _} <- @participant_repo.add_batch(conversation.id, parent_user_ids),
         {:ok, _} <-
           @participant_repo.add_or_get(%{
             conversation_id: conversation.id,
             user_id: scope.user.id
           }) do
      Shared.add_assigned_staff(conversation.id, conversation.program_id, scope.user.id)
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
