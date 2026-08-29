defmodule KlassHero.Messaging.CreateDirectConversation do
  @moduledoc """
  Finds or creates the direct conversation between two people at a provider.

  The single creation path for `:direct` threads. It used to be three — this
  module, `StartProgramConversation`, and a private copy inside
  `ReplyPrivatelyToBroadcast` — which built the same row, seated the same two
  participants, called `AddAssignedStaff`, and emitted the same event. They
  differed only in which id they looked the thread up by, because identity was
  keyed on a single participant and each caller knew a different one of the two.

  With the principal pair on the conversation there is one key, so there is one
  command. Both parties are named explicitly; nothing is inferred from the shape
  of the scope.

  ## What it does

  1. Checks the initiator may start conversations (unless told to skip).
  2. Returns the existing thread between these two, if there is one.
  3. Otherwise inserts the conversation, both principals as participants, and —
     when a `:program_id` is given — the program's assigned staff, inside one
     `Outbox.transact/2`.

  Seated staff are participants, never principals. That is what lets an owner and
  a staff member each hold their own thread with the same parent (#1521), and what
  lets a provider-staff thread exist at all (#747).
  """

  use KlassHero.Shared.Tracing

  alias KlassHero.Accounts.Scope
  alias KlassHero.Messaging.AddAssignedStaff
  alias KlassHero.Messaging.Authorization
  alias KlassHero.Messaging.Conversation
  alias KlassHero.Messaging.Events
  alias KlassHero.Messaging.Notifications
  alias KlassHero.Shared.Outbox

  require Logger

  @context KlassHero.Messaging

  @doc """
  Creates or retrieves the direct conversation between the scope's user and `target_user_id`.

  ## Parameters
  - scope: the initiator's scope (for the entitlement check)
  - provider_id: the provider the thread is anchored to
  - target_user_id: the other principal
  - opts:
    - `:skip_entitlement_check` — bypass the permission check. Used by
      `ReplyPrivatelyToBroadcast` so a parent may reply when the provider
      initiated contact via a broadcast.
    - `:program_id` — associates the thread with a program and seats that
      program's assigned staff. Provider-staff threads leave this `nil`.

  ## Returns
  - `{:ok, conversation}` — new or existing
  - `{:error, :not_entitled}` — the scope may not initiate messaging
  - `{:error, reason}`
  """
  @spec execute(Scope.t(), String.t(), String.t(), keyword()) ::
          {:ok, Conversation.t()}
          | {:error, :not_entitled | term()}
  def execute(%Scope{} = scope, provider_id, target_user_id, opts \\ []) do
    with :ok <- Authorization.maybe_check_entitlement(scope, opts),
         {:ok, target_user_id} <- resolve_target(provider_id, target_user_id) do
      find_or_create_conversation(scope, provider_id, target_user_id, opts)
    end
  end

  # One defaulting rule for every direction: unnamed target means the business
  # itself, i.e. its owner. It is what a parent writing to a provider means, and
  # what a staff member writing to their employer means.
  defp resolve_target(provider_id, nil) do
    acl_span source: "messaging", target: "provider" do
      KlassHero.Provider.get_identity_id_for_provider(provider_id)
    end
  end

  defp resolve_target(_provider_id, target_user_id), do: {:ok, target_user_id}

  defp find_or_create_conversation(scope, provider_id, target_user_id, opts) do
    case KlassHero.Messaging.find_direct_conversation(provider_id, scope.user.id, target_user_id) do
      {:ok, existing} ->
        Logger.debug("Found existing conversation", conversation_id: existing.id)
        {:ok, existing}

      {:error, :not_found} ->
        create_new_conversation(scope, provider_id, target_user_id, opts)
    end
  end

  defp create_new_conversation(scope, provider_id, target_user_id, opts) do
    program_id = Keyword.get(opts, :program_id)
    principals = [scope.user.id, target_user_id]

    Outbox.transact(@context, fn ->
      attrs = Conversation.direct_attrs(provider_id, program_id, scope.user.id, target_user_id)

      with {:ok, conversation} <- KlassHero.Messaging.create_conversation(attrs),
           :ok <- add_participants(conversation.id, principals),
           {:ok, {_staff_ids, staff_events}} <-
             AddAssignedStaff.execute(conversation.id, program_id, principals) do
        created_event =
          Events.conversation_created(
            conversation.id,
            conversation.type,
            provider_id,
            principals,
            conversation.program_id
          )

        {:ok, conversation, [created_event | staff_events]}
      end
    end)
    |> notify_new_conversation(principals)
    |> handle_commit(scope, provider_id)
  end

  # Post-commit, so a list refetching on this sees the conversation. Principals only:
  # `AddAssignedStaff` seats staff into the same thread, but the `:conversation_created`
  # payload the projection notified off carried only the principals, so staff never got
  # this refresh and still do not.
  defp notify_new_conversation({:ok, _conversation} = result, principals) do
    Notifications.conversations_changed_for(principals)
    result
  end

  defp notify_new_conversation(result, _principals), do: result

  defp handle_commit({:ok, conversation}, scope, provider_id) do
    Logger.info("Created direct conversation",
      conversation_id: conversation.id,
      provider_id: provider_id,
      initiator_id: scope.user.id
    )

    {:ok, conversation}
  end

  defp handle_commit({:error, reason}, _scope, _provider_id), do: {:error, reason}

  defp add_participants(conversation_id, user_ids) do
    Enum.reduce_while(user_ids, :ok, fn user_id, :ok ->
      case KlassHero.Messaging.add_participant(%{conversation_id: conversation_id, user_id: user_id}) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
