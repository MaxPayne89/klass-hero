defmodule KlassHero.Messaging.InboxConversation do
  @moduledoc """
  One row of a user's inbox, derived live from the write model.

  A read model with no table behind it — the sibling of
  `KlassHero.Messaging.StaffConversation`, and built the same way, by
  `KlassHero.Messaging.ListConversations`. It replaced the `conversation_summaries`
  projection (ADR-0023): nothing here is stored, so nothing here can drift from the
  conversation it describes. A renamed program shows its new title on the next
  render with no propagation step, which is #896 answered by subtraction.

  ## The field names are the contract

  `KlassHeroWeb.MessagingComponents.conversation_card/1` matches on field *names*,
  not on a struct name, which is what lets one card render this and a
  `StaffConversation` both. Renaming a field here silently changes what that card
  displays — it will not raise, it will fall through to a default clause. The names
  are deliberately the ones the retired read table used.
  """

  @enforce_keys [:conversation_id, :conversation_type]
  defstruct [
    :conversation_id,
    :conversation_type,
    :provider_id,
    :program_id,
    :program_name,
    :other_participant_name,
    :latest_message_content,
    :latest_message_sender_id,
    :latest_message_at,
    enrolled_child_names: [],
    has_attachments: false,
    unread_count: 0
  ]

  @type t :: %__MODULE__{
          conversation_id: String.t(),
          conversation_type: :direct | :program_broadcast,
          provider_id: String.t() | nil,
          program_id: String.t() | nil,
          program_name: String.t() | nil,
          other_participant_name: String.t() | nil,
          latest_message_content: String.t() | nil,
          latest_message_sender_id: String.t() | nil,
          latest_message_at: DateTime.t() | nil,
          enrolled_child_names: [String.t()],
          has_attachments: boolean(),
          unread_count: non_neg_integer()
        }
end
