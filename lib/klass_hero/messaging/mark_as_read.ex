defmodule KlassHero.Messaging.MarkAsRead do
  @moduledoc """
  Use case for marking messages as read in a conversation.

  This use case:
  1. Verifies the user is a participant
  2. Updates last_read_at timestamp
  3. Publishes a messages_read event for real-time updates
  """

  alias KlassHero.Messaging.Domain.Events.MessagingEvents
  alias KlassHero.Messaging.Participant
  alias KlassHero.Shared.Outbox

  require Logger

  @context KlassHero.Messaging

  @doc """
  Marks messages as read for a user in a conversation.

  ## Parameters
  - conversation_id: The conversation
  - user_id: The user marking as read
  - read_at: Optional timestamp (defaults to now)

  ## Returns
  - `{:ok, participant}` - Updated participant
  - `{:error, :not_participant}` - User is not in the conversation
  """
  @spec execute(String.t(), String.t(), DateTime.t() | nil) ::
          {:ok, Participant.t()}
          | {:error, :not_participant}
  def execute(conversation_id, user_id, read_at \\ nil) do
    read_at = read_at || DateTime.utc_now()

    result =
      Outbox.transact(@context, fn ->
        with {:ok, participant} <- KlassHero.Messaging.mark_participant_read(conversation_id, user_id, read_at) do
          {:ok, participant, [MessagingEvents.messages_read(conversation_id, user_id, read_at)]}
        end
      end)

    case result do
      {:ok, participant} ->
        Logger.debug("Marked as read",
          conversation_id: conversation_id,
          user_id: user_id,
          read_at: read_at
        )

        {:ok, participant}

      {:error, :not_found} ->
        {:error, :not_participant}
    end
  end
end
