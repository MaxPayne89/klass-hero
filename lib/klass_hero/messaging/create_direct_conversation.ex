defmodule KlassHero.Messaging.CreateDirectConversation do
  @moduledoc """
  Use case for creating a direct 1-on-1 conversation between a provider and a parent.

  This use case:
  1. Checks if the initiator can start conversations (entitlement check).
  2. Returns an existing direct conversation if one is found.
  3. Otherwise inserts the conversation, the two parties, and (if a
     `:program_id` is provided) the program's assigned staff — all inside a
     single `Repo.transaction`.
  4. After the transaction commits, dispatches the collected domain events
     (`:conversation_created` plus any `:participant_added`) so the
     `ConversationSummaries` projection can read-your-own-writes on a
     separate DB connection.

  Any parent or provider may initiate a conversation (see
  `KlassHero.Messaging.can_initiate_messaging?/1`).
  """

  alias KlassHero.Accounts.Scope
  alias KlassHero.Messaging.AddAssignedStaff
  alias KlassHero.Messaging.Conversation
  alias KlassHero.Messaging.Domain.Events.MessagingEvents
  alias KlassHero.Messaging.Shared
  alias KlassHero.Shared.EventDispatchHelper
  alias KlassHero.Shared.Outbox

  require Logger

  @context KlassHero.Messaging

  @doc """
  Creates or retrieves a direct conversation between provider and user.

  ## Parameters
  - scope: The current user's scope (for entitlement checks)
  - provider_id: The provider's profile ID
  - target_user_id: The user ID to start conversation with
  - opts: Optional keyword list
    - `:skip_entitlement_check` - When `true`, bypasses the permission check.
      Used by ReplyPrivatelyToBroadcast so a parent can reply when the
      provider initiated contact via a broadcast.
    - `:program_id` - When set, associates the conversation with a program and
      auto-adds assigned staff members as participants.

  ## Returns
  - `{:ok, conversation}` - New or existing conversation
  - `{:error, :not_entitled}` - User cannot initiate messaging
  - `{:error, reason}` - Other errors
  """
  @spec execute(Scope.t(), String.t(), String.t(), keyword()) ::
          {:ok, Conversation.t()}
          | {:error, :not_entitled | term()}
  def execute(%Scope{} = scope, provider_id, target_user_id, opts \\ []) do
    with :ok <- Shared.maybe_check_entitlement(scope, opts) do
      find_or_create_conversation(scope, provider_id, target_user_id, opts)
    end
  end

  defp find_or_create_conversation(scope, provider_id, target_user_id, opts) do
    case KlassHero.Messaging.find_direct_conversation(provider_id, target_user_id) do
      {:ok, existing} ->
        Logger.debug("Found existing conversation", conversation_id: existing.id)
        {:ok, existing}

      {:error, :not_found} ->
        create_new_conversation(scope, provider_id, target_user_id, opts)
    end
  end

  defp create_new_conversation(scope, provider_id, target_user_id, opts) do
    program_id = Keyword.get(opts, :program_id)

    Outbox.transact(@context, fn ->
      attrs =
        %{type: :direct, provider_id: provider_id}
        |> Shared.maybe_put_program_id(program_id)

      with {:ok, conversation} <- KlassHero.Messaging.create_conversation(attrs),
           :ok <- add_participants(conversation.id, scope.user.id, target_user_id),
           {:ok, {_staff_ids, staff_events}} <-
             AddAssignedStaff.execute(conversation.id, program_id, scope.user.id) do
        created_event =
          MessagingEvents.conversation_created(
            conversation.id,
            conversation.type,
            provider_id,
            [scope.user.id, target_user_id],
            conversation.program_id
          )

        {:ok, conversation, [created_event | staff_events]}
      end
    end)
    |> handle_commit(scope, provider_id)
  end

  # Cross-context delivery committed with the conversation; this is the same-context
  # remainder — the LiveView notifier.
  defp handle_commit({:ok, {conversation, events}}, scope, provider_id) do
    Enum.each(events, &EventDispatchHelper.dispatch(&1, @context))

    Logger.info("Created direct conversation",
      conversation_id: conversation.id,
      provider_id: provider_id,
      initiator_id: scope.user.id
    )

    {:ok, conversation}
  end

  defp handle_commit({:error, reason}, _scope, _provider_id), do: {:error, reason}

  defp add_participants(conversation_id, user_id_1, user_id_2) do
    with {:ok, _} <-
           KlassHero.Messaging.add_participant(%{conversation_id: conversation_id, user_id: user_id_1}),
         {:ok, _} <-
           KlassHero.Messaging.add_participant(%{conversation_id: conversation_id, user_id: user_id_2}) do
      :ok
    end
  end
end
