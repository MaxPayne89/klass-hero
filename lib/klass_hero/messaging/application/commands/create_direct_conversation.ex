defmodule KlassHero.Messaging.Application.Commands.CreateDirectConversation do
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

  Free-tier parents cannot initiate conversations but can receive and reply to them.
  """

  alias KlassHero.Accounts.Scope
  alias KlassHero.Messaging.Application.Commands.AddAssignedStaff
  alias KlassHero.Messaging.Application.Shared
  alias KlassHero.Messaging.Domain.Events.MessagingEvents
  alias KlassHero.Messaging.Domain.Models.Conversation
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

  @doc """
  Creates or retrieves a direct conversation between provider and user.

  ## Parameters
  - scope: The current user's scope (for entitlement checks)
  - provider_id: The provider's profile ID
  - target_user_id: The user ID to start conversation with
  - opts: Optional keyword list
    - `:skip_entitlement_check` - When `true`, bypasses the entitlement check.
      Used by ReplyPrivatelyToBroadcast so that any tier can reply when the
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
    case @conversation_reader.find_direct_conversation(provider_id, target_user_id) do
      {:ok, existing} ->
        Logger.debug("Found existing conversation", conversation_id: existing.id)
        {:ok, existing}

      {:error, :not_found} ->
        create_new_conversation(scope, provider_id, target_user_id, opts)
    end
  end

  defp create_new_conversation(scope, provider_id, target_user_id, opts) do
    program_id = Keyword.get(opts, :program_id)

    Repo.transaction(fn ->
      attrs =
        %{type: :direct, provider_id: provider_id}
        |> maybe_put_program_id(program_id)

      with {:ok, conversation} <- @conversation_repo.create(attrs),
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

        {conversation, [created_event | staff_events]}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> handle_commit(scope, provider_id)
  end

  # Trigger: Repo.transaction returns {:ok, {conversation, events}}
  # Why: events must be dispatched *after* commit so the projection — which
  #      reads the write tables from a separate DB connection — can see the
  #      committed conversation row when it processes the integration event.
  # Outcome: events fan out via EventDispatchHelper.dispatch/2 (fire-and-
  #          forget; critical events get Oban-backed retry on publish failure).
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

  defp maybe_put_program_id(attrs, nil), do: attrs
  defp maybe_put_program_id(attrs, program_id), do: Map.put(attrs, :program_id, program_id)

  defp add_participants(conversation_id, user_id_1, user_id_2) do
    with {:ok, _} <-
           @participant_repo.add(%{conversation_id: conversation_id, user_id: user_id_1}),
         {:ok, _} <-
           @participant_repo.add(%{conversation_id: conversation_id, user_id: user_id_2}) do
      :ok
    end
  end
end
