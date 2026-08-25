defmodule KlassHero.Messaging.GetStaffConversation do
  @moduledoc """
  Reads one conversation's full thread for a provider owner who is not a participant.

  The owner counterpart to `KlassHero.Messaging.GetMonitoredConversation`, and
  deliberately not a flag on it. Two things differ, both load-bearing:

  **Ownership is re-checked against the row.** `authorize_admin/1` grants blanket
  visibility, so past that gate any conversation id is fair game. Owner authorization
  proves only that the scope owns *a* provider — never that it owns *this*
  conversation. The fetch therefore carries both predicates, and a row belonging to
  another business comes back `nil`, indistinguishable from an id that never existed.
  Without that, a pasted UUID would read a competitor's threads.

  **`:not_found` is genuinely one answer.** Because both predicates ride in a single
  `Repo.one/1`, "wrong owner" and "doesn't exist" cannot be told apart at any cost —
  there is no enumeration oracle here of the kind ADR-0017 warns about and
  `GetConversation` still carries (#1515).

  **There is no `:mark_as_read` option**, for the reason `GetMonitoredConversation`
  records: `Participant.last_read_at` feeds three independent unread counters, and an
  owner viewing a thread must never move somebody else's. Omitting the option makes
  that unexpressible rather than merely unused.
  """

  use KlassHero.Shared.Tracing

  alias KlassHero.Accounts.Scope
  alias KlassHero.Messaging.Authorization
  alias KlassHero.Messaging.Queries.ConversationQueries
  alias KlassHero.Repo

  require Logger

  @doc """
  Returns `%{conversation:, messages:, has_more:, sender_names:}` for a conversation
  the calling owner's provider owns.

  ## Options

    * `:limit` - messages per page
    * `:before` - exclusive `inserted_at` cursor for older messages
  """
  @spec execute(Scope.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, :unauthorized | :not_found}
  def execute(%Scope{} = scope, conversation_id, opts \\ []) do
    # The span and the log line together are the access trail: which owner read which
    # thread, when. There is no durable access-log table — see ADR-0021.
    span do
      OpenTelemetry.Tracer.set_attribute("messaging.staff_conversations.owner_id", scope.user.id)

      OpenTelemetry.Tracer.set_attribute(
        "messaging.staff_conversations.conversation_id",
        conversation_id
      )

      with {:ok, provider_id} <- Authorization.authorize_provider_owner(scope),
           {:ok, conversation} <- fetch_owned(conversation_id, provider_id),
           {:ok, messages, sender_names, has_more} <-
             KlassHero.Messaging.list_messages_with_senders(conversation_id, opts) do
        Logger.info("Provider owner read a staff conversation they are not a participant of",
          conversation_id: conversation_id,
          provider_id: provider_id,
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

  defp fetch_owned(conversation_id, provider_id) do
    ConversationQueries.base()
    |> ConversationQueries.by_id(conversation_id)
    |> ConversationQueries.by_provider(provider_id)
    |> ConversationQueries.preload_assocs([:participants])
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      conversation -> {:ok, conversation}
    end
  end
end
