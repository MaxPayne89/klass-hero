defmodule KlassHero.Messaging.Application.Commands.StartProgramConversation do
  @moduledoc """
  Use case for a parent initiating a direct conversation about a specific program.

  Looks up by the initiating parent's user_id (uniquely 1:1 with a
  (parent, provider) direct conversation), and on miss creates a new
  conversation with program context — auto-adding program-assigned staff
  as participants and publishing a `conversation_created` event.
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
  @user_resolver Application.compile_env!(:klass_hero, [:messaging, :for_resolving_users])

  @spec execute(Scope.t(), String.t(), String.t()) ::
          {:ok, Conversation.t()} | {:error, :not_found | :not_entitled | term()}
  def execute(%Scope{} = scope, provider_id, program_id) do
    with :ok <- Shared.maybe_check_entitlement(scope, []),
         {:ok, owner_user_id} <- @user_resolver.get_user_id_for_provider(provider_id) do
      find_or_create(scope, provider_id, program_id, owner_user_id)
    end
  end

  # Lookup by parent's user_id (not provider's) — provider owner participates in all
  # direct conversations, so using their id would collide across parents.
  # See ReplyPrivatelyToBroadcast for the same pattern.
  defp find_or_create(scope, provider_id, program_id, owner_user_id) do
    case @conversation_reader.find_direct_conversation(provider_id, scope.user.id) do
      {:ok, existing} ->
        {:ok, existing}

      {:error, :not_found} ->
        create_new_conversation(scope, provider_id, program_id, owner_user_id)
    end
  end

  defp create_new_conversation(scope, provider_id, program_id, owner_user_id) do
    attrs = %{type: :direct, provider_id: provider_id, program_id: program_id}

    Repo.transaction(fn ->
      with {:ok, conversation} <- @conversation_repo.create(attrs),
           :ok <- add_participants(conversation.id, scope.user.id, owner_user_id),
           {:ok, {_staff_ids, staff_events}} <-
             AddAssignedStaff.execute(conversation.id, program_id, scope.user.id) do
        created_event =
          MessagingEvents.conversation_created(
            conversation.id,
            conversation.type,
            provider_id,
            [scope.user.id, owner_user_id],
            conversation.program_id
          )

        {conversation, [created_event | staff_events]}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> handle_commit(scope, provider_id, program_id)
  end

  # Dispatch post-commit so the projection's separate DB connection sees the committed row.
  defp handle_commit({:ok, {conversation, events}}, scope, provider_id, program_id) do
    Enum.each(events, &EventDispatchHelper.dispatch(&1, @context))

    Logger.info("Created program-scoped direct conversation",
      conversation_id: conversation.id,
      provider_id: provider_id,
      program_id: program_id,
      initiator_id: scope.user.id
    )

    {:ok, conversation}
  end

  defp handle_commit({:error, reason}, _scope, _provider_id, _program_id), do: {:error, reason}

  defp add_participants(conversation_id, user_id_1, user_id_2) do
    with {:ok, _} <-
           @participant_repo.add(%{conversation_id: conversation_id, user_id: user_id_1}),
         {:ok, _} <-
           @participant_repo.add(%{conversation_id: conversation_id, user_id: user_id_2}) do
      :ok
    end
  end
end
