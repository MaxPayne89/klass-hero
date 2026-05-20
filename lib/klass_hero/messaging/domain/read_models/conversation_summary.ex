defmodule KlassHero.Messaging.Domain.ReadModels.ConversationSummary do
  @moduledoc """
  Read-optimized DTO for conversation summaries.

  Lightweight struct for inbox display — no business logic.
  Populated from the denormalized conversation_summaries read table.
  """

  @typedoc "A denormalized conversation summary for inbox display."
  @type t :: %__MODULE__{
          id: String.t(),
          conversation_id: String.t(),
          user_id: String.t(),
          conversation_type: String.t(),
          provider_id: String.t(),
          program_id: String.t() | nil,
          subject: String.t() | nil,
          other_participant_name: String.t() | nil,
          program_name: String.t() | nil,
          participant_count: non_neg_integer(),
          latest_message_content: String.t() | nil,
          latest_message_sender_id: String.t() | nil,
          latest_message_at: DateTime.t() | nil,
          has_attachments: boolean(),
          unread_count: non_neg_integer(),
          last_read_at: DateTime.t() | nil,
          archived_at: DateTime.t() | nil,
          enrolled_child_names: [String.t()],
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @enforce_keys [:id, :conversation_id, :user_id, :conversation_type, :provider_id]

  defstruct [
    :id,
    :conversation_id,
    :user_id,
    :conversation_type,
    :provider_id,
    :program_id,
    :subject,
    :other_participant_name,
    :program_name,
    :latest_message_content,
    :latest_message_sender_id,
    :latest_message_at,
    :last_read_at,
    :archived_at,
    :inserted_at,
    :updated_at,
    has_attachments: false,
    participant_count: 0,
    unread_count: 0,
    enrolled_child_names: []
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    struct!(__MODULE__, attrs)
  end
end
