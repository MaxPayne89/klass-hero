defmodule KlassHero.Messaging.ReplyPrivatelyToBroadcast do
  @moduledoc """
  Use case for privately replying to a broadcast message.

  Finds or creates a direct conversation with the broadcast's provider, inserts
  a deduped system note referencing the broadcast, and returns the direct
  conversation ID for navigation.
  """

  use KlassHero.Shared.Tracing

  alias KlassHero.Accounts.Scope
  alias KlassHero.Messaging
  alias KlassHero.Messaging.Authorization
  alias KlassHero.Messaging.CreateDirectConversation

  require Logger

  @doc """
  Orchestrates a private reply to a broadcast.

  ## Returns
  - `{:ok, direct_conversation_id}`
  - `{:error, :not_found}` — broadcast conversation not found
  - `{:error, reason}`
  """
  @spec execute(Scope.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def execute(%Scope{} = scope, broadcast_conversation_id) do
    # Defense in depth: get_by_id doesn't verify type or participant status;
    # pattern match on :program_broadcast + participation check ensures only
    # broadcast participants can initiate private replies.
    with {:ok, broadcast} <- fetch_broadcast(broadcast_conversation_id),
         :ok <- Authorization.verify_participant(broadcast.id, scope.user.id),
         {:ok, provider_user_id} <- provider_owner_user_id(broadcast.provider_id),
         {:ok, direct_conversation} <-
           find_or_create_direct_conversation(
             scope,
             broadcast.provider_id,
             provider_user_id,
             broadcast.program_id
           ),
         :ok <-
           maybe_insert_system_note(
             direct_conversation,
             scope.user.id,
             broadcast
           ) do
      Logger.info("Private reply to broadcast initiated",
        broadcast_id: broadcast_conversation_id,
        direct_conversation_id: direct_conversation.id,
        user_id: scope.user.id
      )

      {:ok, direct_conversation.id}
    end
  end

  defp provider_owner_user_id(provider_id) do
    acl_span source: "messaging", target: "provider" do
      KlassHero.Provider.get_identity_id_for_provider(provider_id)
    end
  end

  defp fetch_broadcast(conversation_id) do
    case KlassHero.Messaging.get_conversation_by_id(conversation_id) do
      {:ok, %{type: :program_broadcast} = broadcast} -> {:ok, broadcast}
      {:ok, _non_broadcast} -> {:error, :not_broadcast}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  # The entitlement check is skipped, not bypassed by accident: the provider
  # opened the conversation by broadcasting, so the parent may answer it even on
  # a plan that would not let them start one.
  defp find_or_create_direct_conversation(scope, provider_id, provider_user_id, program_id) do
    CreateDirectConversation.execute(scope, provider_id, provider_user_id,
      program_id: program_id,
      skip_entitlement_check: true
    )
  end

  # Inserts a system note referencing the broadcast so the provider knows context.
  # Dedup prevents duplicate notes if the parent taps "Reply privately" multiple times.
  defp maybe_insert_system_note(direct_conversation, sender_id, broadcast) do
    token = "[broadcast:#{broadcast.id}]"

    if system_note_exists?(direct_conversation.id, token) do
      :ok
    else
      subject = broadcast.subject || "broadcast"
      content = "#{token} Re: #{subject}"

      # Sending the message *is* recording the token, so there is no second write
      # to race: the dedup check reads the message back.
      with {:ok, _message} <-
             Messaging.send_message(direct_conversation.id, sender_id, content,
               message_type: :system,
               conversation: direct_conversation
             ) do
        :ok
      end
    end
  end

  defp system_note_exists?(conversation_id, token) do
    KlassHero.Messaging.has_system_note?(conversation_id, token)
  end
end
