defmodule KlassHero.Messaging.ListConversations do
  @moduledoc """
  Use case for listing a user's conversations.

  Reads from the denormalized conversation_summaries read model (CQRS read side).
  Returns conversations ordered by most recent message, with unread counts
  and other participant info pre-computed in the read model.
  """

  require Logger

  @doc """
  Lists conversations for a user.

  ## Parameters
  - user_id: The user to list conversations for
  - opts: Optional parameters
    - limit: Number of conversations to return (default 25)

  ## Returns
  - `{:ok, conversations, has_more}` - List of conversations with unread counts

  Each conversation map includes:
  - `:conversation` - Map with id, type, provider_id, program_id, subject
  - `:unread_count` - Number of unread messages
  - `:latest_message` - The most recent message (map or nil)
  - `:last_read_at` - When user last read
  - `:other_participant_name` - Display name of the other participant for
    direct conversations; nil for broadcasts (which use `:program_name`)
  - `:program_name` - Program title for `:program_broadcast` conversations;
    nil for direct (denormalised from `programs.title` by the projection)
  - `:enrolled_child_names` - List of child first names attached to the
    conversation (provider-side context for direct conversations)
  """
  @spec execute(String.t(), keyword()) ::
          {:ok, [map()], boolean()}
  def execute(user_id, opts \\ []) do
    {:ok, summaries, has_more} = KlassHero.Messaging.list_conversation_summaries_for_user(user_id, opts)

    enriched = Enum.map(summaries, &to_enriched_map/1)

    Logger.debug("Listed conversations",
      user_id: user_id,
      count: length(enriched)
    )

    {:ok, enriched, has_more}
  end

  # Maps ConversationSummary DTO to the enriched map shape expected by LiveView templates.
  defp to_enriched_map(summary) do
    %{
      conversation: %{
        id: summary.conversation_id,
        type: summary.conversation_type,
        provider_id: summary.provider_id,
        program_id: summary.program_id,
        subject: summary.subject
      },
      unread_count: summary.unread_count,
      latest_message: build_latest_message(summary),
      last_read_at: summary.last_read_at,
      other_participant_name: summary.other_participant_name,
      program_name: summary.program_name,
      enrolled_child_names: summary.enrolled_child_names
    }
  end

  defp build_latest_message(%{latest_message_content: nil, has_attachments: false}), do: nil
  defp build_latest_message(summary), do: do_build_latest_message(summary)

  defp do_build_latest_message(summary) do
    %{
      content: summary.latest_message_content,
      sender_id: summary.latest_message_sender_id,
      inserted_at: summary.latest_message_at,
      has_attachments: summary.has_attachments
    }
  end
end
