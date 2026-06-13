defmodule KlassHero.Messaging.Application.Commands.ReplyPrivatelyToBroadcast do
  @moduledoc """
  Use case for privately replying to a broadcast message.

  Finds or creates a direct conversation with the broadcast's provider, inserts
  a deduped system note referencing the broadcast, and returns the direct
  conversation ID for navigation.
  """

  alias KlassHero.Accounts.Scope
  alias KlassHero.Messaging
  alias KlassHero.Messaging.Application.Commands.AddAssignedStaff
  alias KlassHero.Messaging.Application.Shared
  alias KlassHero.Messaging.Domain.Events.MessagingEvents
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

  # Lookup by parent's user_id (not provider's) — uniquely identifies this (parent, provider)
  # pair. Provider-user lookup would collide across multiple parents.
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
        |> Shared.maybe_put_program_id(program_id)

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
           {:ok, {_staff_ids, staff_events}} <-
             AddAssignedStaff.execute(conversation.id, program_id, provider_user_id) do
        created_event =
          MessagingEvents.conversation_created(
            conversation.id,
            conversation.type,
            provider_id,
            [scope.user.id, provider_user_id],
            conversation.program_id
          )

        {conversation, [created_event | staff_events]}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> handle_commit()
  end

  # Dispatch post-commit so the ConversationSummaries projection (separate DB
  # connection) can read the committed row when it processes these events.
  defp handle_commit({:ok, {conversation, events}}) do
    Enum.each(events, &EventDispatchHelper.dispatch(&1, @context))
    {:ok, conversation}
  end

  defp handle_commit({:error, reason}), do: {:error, reason}

  # Inserts a system note referencing the broadcast so the provider knows context.
  # Dedup prevents duplicate notes if the parent taps "Reply privately" multiple times.
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
        # Write-through: projection processes message_sent asynchronously; without
        # this, a rapid second call could miss the token and insert a duplicate.
        # Projection's async handler is idempotent, so the double-write is harmless.
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
