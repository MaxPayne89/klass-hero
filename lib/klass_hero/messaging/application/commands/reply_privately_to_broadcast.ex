defmodule KlassHero.Messaging.Application.Commands.ReplyPrivatelyToBroadcast do
  @moduledoc """
  Use case for privately replying to a broadcast message.

  When a parent wants to respond to a broadcast, this use case:
  1. Fetches the broadcast conversation to get the provider
  2. Creates (or finds) a direct conversation with that provider
  3. Inserts a system message for context (idempotent)
  4. Returns the direct conversation ID for navigation
  """

  alias KlassHero.Accounts.Scope
  alias KlassHero.Messaging
  alias KlassHero.Messaging.Application.Shared
  alias KlassHero.Messaging.Domain.Events.MessagingEvents
  alias KlassHero.Repo
  alias KlassHero.Shared.DomainEventBus

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
  @participant_repo Application.compile_env!(:klass_hero, [:messaging, :for_managing_participants])
  @participant_reader Application.compile_env!(:klass_hero, [:messaging, :for_querying_participants])
  @user_resolver Application.compile_env!(:klass_hero, [:messaging, :for_resolving_users])
  @conversation_summaries_repo Application.compile_env!(:klass_hero, [
                                 :messaging,
                                 :for_managing_conversation_summaries
                               ])
  @conversation_summaries_reader Application.compile_env!(:klass_hero, [
                                   :messaging,
                                   :for_querying_conversation_summaries
                                 ])

  @doc """
  Orchestrates a private reply to a broadcast.

  ## Parameters
  - scope: The parent's scope
  - broadcast_conversation_id: The broadcast conversation being replied to

  ## Returns
  - `{:ok, direct_conversation_id}` - Direct conversation ready for messaging
  - `{:error, :not_found}` - Broadcast conversation not found
  - `{:error, reason}` - Other errors
  """
  @spec execute(Scope.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def execute(%Scope{} = scope, broadcast_conversation_id) do
    # Trigger: crafted call with a non-broadcast or unauthorized conversation ID
    # Why: get_by_id doesn't verify type or participant status — pattern match
    #      on :program_broadcast and check participation for defense in depth
    # Outcome: only broadcast participants can initiate private replies
    with {:ok, broadcast} <- fetch_broadcast(broadcast_conversation_id),
         :ok <- Shared.verify_participant(broadcast.id, scope.user.id, @participant_reader),
         {:ok, provider_user_id} <- @user_resolver.get_user_id_for_provider(broadcast.provider_id),
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

  defp fetch_broadcast(conversation_id) do
    case @conversation_reader.get_by_id(conversation_id) do
      {:ok, %{type: :program_broadcast} = broadcast} -> {:ok, broadcast}
      {:ok, _non_broadcast} -> {:error, :not_broadcast}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  # Trigger: parent wants a direct conversation with the broadcast's provider
  # Why: find_direct_conversation(provider_id, user_id) expects the NON-PROVIDER
  #      user as the lookup key — the parent's user_id uniquely identifies the
  #      conversation. CreateDirectConversation was designed for provider-initiated
  #      flows and searches by target_user_id, which doesn't work when the parent
  #      is the initiator (it would match any provider conversation).
  #      We handle find and create separately to get the correct lookup semantics.
  # Outcome: returns the unique direct conversation between this parent and provider
  defp find_or_create_direct_conversation(scope, provider_id, provider_user_id, program_id) do
    case @conversation_reader.find_direct_conversation(provider_id, scope.user.id) do
      {:ok, existing} ->
        {:ok, existing}

      {:error, :not_found} ->
        create_direct_conversation(scope, provider_id, provider_user_id, program_id)
    end
  end

  defp create_direct_conversation(scope, provider_id, provider_user_id, program_id) do
    Repo.transaction(fn ->
      attrs =
        %{type: :direct, provider_id: provider_id}
        |> maybe_put_program_id(program_id)

      with {:ok, conversation} <- @conversation_repo.create(attrs),
           {:ok, _} <-
             @participant_repo.add(%{
               conversation_id: conversation.id,
               user_id: scope.user.id
             }),
           {:ok, _} <-
             @participant_repo.add(%{
               conversation_id: conversation.id,
               user_id: provider_user_id
             }),
           :ok <- Shared.add_assigned_staff(conversation.id, program_id, provider_user_id) do
        publish_conversation_created(conversation, scope.user.id, provider_user_id, provider_id)
        conversation
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp maybe_put_program_id(attrs, nil), do: attrs
  defp maybe_put_program_id(attrs, program_id), do: Map.put(attrs, :program_id, program_id)

  defp publish_conversation_created(conversation, parent_user_id, provider_user_id, provider_id) do
    event =
      MessagingEvents.conversation_created(
        conversation.id,
        conversation.type,
        provider_id,
        [parent_user_id, provider_user_id],
        conversation.program_id
      )

    DomainEventBus.dispatch(@context, event)
  end

  # Trigger: parent initiates a private reply to a broadcast
  # Why: inserts a system note in the direct conversation so the provider
  #      knows which broadcast prompted the message. Dedup prevents duplicate
  #      notes if the parent taps "Reply privately" multiple times.
  # Outcome: exactly one system note per broadcast reference in the conversation
  defp maybe_insert_system_note(direct_conversation, sender_id, broadcast) do
    token = "[broadcast:#{broadcast.id}]"

    if system_note_exists?(direct_conversation.id, token) do
      :ok
    else
      subject = broadcast.subject || "broadcast"
      content = "#{token} Re: #{subject}"

      with {:ok, _message} <-
             Messaging.send_message(direct_conversation.id, sender_id, content,
               message_type: :system,
               conversation: direct_conversation
             ) do
        # Trigger: system note just written to messages table
        # Why: the projection processes message_sent events asynchronously —
        #      without this write-through, a rapid second call could miss the
        #      token and insert a duplicate
        # Outcome: token immediately visible in the projection table; the
        #          projection's async handler is idempotent and harmless
        try do
          @conversation_summaries_repo.write_system_note_token(
            direct_conversation.id,
            token
          )
        rescue
          error ->
            Logger.warning("write_system_note_token failed — projection will catch up",
              conversation_id: direct_conversation.id,
              error: Exception.message(error)
            )
        end

        :ok
      end
    end
  end

  defp system_note_exists?(conversation_id, token) do
    @conversation_summaries_reader.has_system_note?(conversation_id, token)
  end
end
