defmodule KlassHero.Messaging.GetMonitoredConversation do
  @moduledoc """
  Reads one conversation's full thread for a platform admin who is not a participant.

  The admin counterpart to `KlassHero.Messaging.GetConversation`, and deliberately not
  a flag on it. Two differences from that module are load-bearing:

  **Authorization runs first.** `GetConversation` fetches the conversation *before*
  checking the participant row, so its `:not_found` and `:not_participant` are
  distinguishable to a caller — the enumeration oracle ADR-0017 warns about. Here the
  admin check comes first, so a non-admin gets `:unauthorized` whatever id they pass,
  and past the gate an admin is entitled to know whether a conversation exists anyway.

  **There is no `:mark_as_read` option.** `GetConversation.execute/3` has one, so it
  can be passed by mistake. `Participant.last_read_at` is the sole input to every
  unread count in the system — the nav badge and each card badge both read it live
  (ADR-0023) — so an admin viewing a thread must never touch it. Omitting the option
  makes that unexpressible rather than merely unused.
  """

  use KlassHero.Shared.Tracing

  alias KlassHero.Accounts.Scope
  alias KlassHero.Messaging.Authorization

  require Logger

  @doc """
  Returns `%{conversation:, messages:, has_more:, sender_names:}` for any conversation.

  ## Options

    * `:limit` - messages per page
    * `:before` - exclusive `inserted_at` cursor for older messages
  """
  @spec execute(Scope.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, :unauthorized | :not_found}
  def execute(%Scope{} = scope, conversation_id, opts \\ []) do
    # The span and the log line together are the access trail: who read which
    # conversation, when. There is no durable access-log table — see ADR-0021.
    span do
      OpenTelemetry.Tracer.set_attribute("messaging.monitoring.admin_id", scope.user.id)
      OpenTelemetry.Tracer.set_attribute("messaging.monitoring.conversation_id", conversation_id)

      with :ok <- Authorization.authorize_admin(scope),
           {:ok, conversation} <-
             KlassHero.Messaging.get_conversation_by_id(conversation_id, preload: [:participants]),
           {:ok, messages, sender_names, has_more} <-
             KlassHero.Messaging.list_messages_with_senders(conversation_id, opts) do
        Logger.info("Admin read a conversation they are not a participant of",
          conversation_id: conversation_id,
          user_id: scope.user.id
        )

        {:ok,
         %{
           conversation: conversation,
           messages: messages,
           has_more: has_more,
           sender_names: sender_names
         }}
      end
    end
  end
end
