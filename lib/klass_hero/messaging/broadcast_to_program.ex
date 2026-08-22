defmodule KlassHero.Messaging.BroadcastToProgram do
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

  use KlassHero.Shared.Tracing

  alias KlassHero.Accounts.Scope
  alias KlassHero.Messaging.AddAssignedStaff
  alias KlassHero.Messaging.Conversation
  alias KlassHero.Messaging.Domain.Events.MessagingEvents
  alias KlassHero.Messaging.Message
  alias KlassHero.Messaging.SendMessage
  alias KlassHero.Messaging.Shared
  alias KlassHero.ProgramCatalog
  alias KlassHero.Shared.Outbox

  require Logger

  @context KlassHero.Messaging

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
    - provider_id: Acting provider ID (defaults to scope.provider.id). Required
      when scope.provider is nil (e.g. staff member scopes). Authorised against
      the scope — a provider the scope neither owns nor staffs is rejected.
    - skip_entitlement_check: When true, skips the entitlement check.
      Caller is responsible for verifying entitlements before calling.

  ## Returns
  - `{:ok, conversation, message, recipient_count}` - Broadcast sent
  - `{:error, :not_found}` - The program doesn't exist, doesn't belong to the
    acting provider, or the scope isn't authorised to act as that provider
    (all three collapse to one atom so ids can't be probed)
  - `{:error, :not_entitled}` - Provider cannot send broadcasts
  - `{:error, :no_enrollments}` - No enrolled parents to broadcast to
  - `{:error, :missing_provider_id}` - Could not resolve a provider_id
  - `{:error, reason}` - Errors surfaced from `SendMessage` (validation, upload, persistence)
  """
  @spec execute(Scope.t(), String.t(), String.t(), keyword()) ::
          {:ok, Conversation.t(), Message.t(), non_neg_integer()}
          | {:error,
             :not_found
             | :not_entitled
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
    subject = Keyword.get(opts, :subject)
    attachments = Keyword.get(opts, :attachments, [])
    # normalize_content: attachment-only broadcasts submit "" which must become nil
    # to match direct-message behaviour (SendMessage.trim_content/1 preserves "").
    normalized_content = normalize_content(content, attachments)

    # Authorise before touching anything: the acting provider must be bound to
    # the scope, and the program must belong to that provider. Both guards are
    # defence-in-depth — callers are expected to check too — but they keep the
    # facade safe on its own.
    with {:ok, provider_id} <- Shared.resolve_acting_provider(scope, opts),
         {:ok, _program} <- ProgramCatalog.get_program_for_provider(provider_id, program_id),
         # Vestigial today: ADR-0004 removed provider tiers, so this can only
         # reject a staff-shaped scope that omits skip_entitlement_check — a
         # shape no caller produces. Kept as the seam for the planned
         # success-fee model, not as active defence.
         :ok <- Shared.maybe_check_entitlement(scope, opts, provider_id: provider_id),
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
    acl_span source: "messaging", target: "enrollment" do
      {:ok, KlassHero.Enrollment.list_enrolled_identity_ids(program_id)}
    end
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

  defp setup_participants(conversation, scope, parent_user_ids) do
    # De-dupe: provider user may also be enrolled as a parent.
    candidate_ids = Enum.uniq([scope.user.id | parent_user_ids])

    Outbox.transact(@context, fn ->
      with {:ok, inserted} <- KlassHero.Messaging.add_participants(conversation.id, candidate_ids),
           {:ok, {_staff_ids, staff_events}} <-
             AddAssignedStaff.execute(conversation.id, conversation.program_id, scope.user.id) do
        {:ok, :ok, build_broadcast_event(conversation.id, inserted) ++ staff_events}
      end
    end)
    |> case do
      {:ok, :ok} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_broadcast_event(_conversation_id, []), do: []

  defp build_broadcast_event(conversation_id, inserted) do
    user_ids = Enum.map(inserted, & &1.user_id)
    [MessagingEvents.participant_added(conversation_id, user_ids, :broadcast_setup)]
  end

  defp get_or_create_broadcast_conversation(provider_id, program_id, subject) do
    # Check before insert to avoid unique constraint violation aborting a parent transaction.
    case KlassHero.Messaging.find_active_broadcast_for_program(provider_id, program_id) do
      {:ok, conversation} ->
        {:ok, conversation}

      {:error, :not_found} ->
        attrs = %{
          type: :program_broadcast,
          provider_id: provider_id,
          program_id: program_id,
          subject: subject
        }

        case KlassHero.Messaging.create_conversation(attrs) do
          {:ok, conversation} ->
            {:ok, conversation}

          # Race: another request won between our find and create; re-query for the winner.
          {:error, :duplicate_broadcast} ->
            KlassHero.Messaging.find_active_broadcast_for_program(provider_id, program_id)
        end
    end
  end
end
