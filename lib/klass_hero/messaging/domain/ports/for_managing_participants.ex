defmodule KlassHero.Messaging.Domain.Ports.ForManagingParticipants do
  @moduledoc """
  Write-only port for managing conversation participants in the Messaging bounded context.

  This behaviour defines the contract for participant mutation operations.
  Read operations are defined in `ForQueryingParticipants`.
  Implemented by adapters in the infrastructure layer.
  """

  alias KlassHero.Messaging.Domain.Models.Participant

  @doc """
  Adds a participant to a conversation.

  Returns:
  - `{:ok, Participant.t()}` - Participant added
  - `{:error, :already_participant}` - User already in conversation
  - `{:error, changeset}` - Validation failure
  """
  @callback add(attrs :: map()) ::
              {:ok, Participant.t()} | {:error, :already_participant | term()}

  @doc """
  Adds a participant if not already present, or returns the existing one.

  Idempotent variant of `add/1`. Safe to call inside a `Repo.transaction` for
  a `(conversation_id, user_id)` pair that may already exist — the underlying
  insert uses `on_conflict: :nothing` so the unique-constraint violation never
  fires and the surrounding transaction is not poisoned.

  Returns:
  - `{:ok, Participant.t()}` - Either the newly inserted or the pre-existing participant
  - `{:error, :not_found}` - Insert was skipped on conflict but the row could not be re-fetched
  """
  @callback add_or_get(attrs :: map()) ::
              {:ok, Participant.t()} | {:error, term()}

  @doc """
  Updates the last_read_at timestamp for a participant.

  Returns:
  - `{:ok, Participant.t()}` - Updated successfully
  - `{:error, :not_found}` - Participant not found
  """
  @callback mark_as_read(
              conversation_id :: binary(),
              user_id :: binary(),
              read_at :: DateTime.t()
            ) ::
              {:ok, Participant.t()} | {:error, :not_found}

  @doc """
  Removes a participant from a conversation.

  Sets left_at timestamp rather than deleting.
  """
  @callback leave(conversation_id :: binary(), user_id :: binary()) ::
              {:ok, Participant.t()} | {:error, :not_found}

  @doc """
  Marks all active participations as left for a user.

  Sets `left_at` on all participant records where `user_id` matches
  and `left_at` is nil. Used for GDPR data anonymization.

  Returns:
  - `{:ok, count}` - Number of participant records updated
  - `{:error, :database_connection_error}` - Database connection failure
  - `{:error, :database_query_error}` - Database query failure
  """
  @callback mark_all_as_left(user_id :: binary()) ::
              {:ok, non_neg_integer()}
              | {:error, :database_connection_error | :database_query_error}

  @doc """
  Adds multiple participants to a conversation in a batch.

  Used for program broadcasts to add all enrolled parents.
  """
  @callback add_batch(conversation_id :: binary(), user_ids :: [binary()]) ::
              {:ok, [Participant.t()]}

  @doc """
  Adds a user as a participant to multiple conversations in a batch.

  Used when adding a staff member to all existing program conversations.
  Silently skips conversations where the user is already a participant.

  Returns `{:ok, count}` — number of new participant records inserted.
  """
  @callback add_to_conversations_batch(user_id :: binary(), conversation_ids :: [binary()]) ::
              {:ok, non_neg_integer()}
end
