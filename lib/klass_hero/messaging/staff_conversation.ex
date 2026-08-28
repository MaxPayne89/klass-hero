defmodule KlassHero.Messaging.StaffConversation do
  @moduledoc """
  Read row for a provider owner's "Staff conversations" list (#746): a conversation
  their business owns but that they are not a participant of.

  A query-shaped struct over the **write** tables (`conversations`,
  `conversation_participants`, `messages`), built by
  `KlassHero.Messaging.ListStaffConversations`. Plain struct — no Ecto schema, no
  table, no changeset. It sits at the context root rather than under `read_models/`
  because that kind earns a directory at three files and Messaging has two — this and
  `KlassHero.Messaging.InboxConversation`.

  Every other read in this context is keyed by a participant, and an owner reading a
  thread they are not in is not one — the same reasoning `MonitorConversations` records
  for the admin list. So this is built from the write tables directly.

  ## Why the field names match `InboxConversation`

  `KlassHeroWeb.MessagingComponents.conversation_card/1` is declared `attr :summary,
  :map` and its helpers match on field *names*, not on a struct name. Carrying the
  same names lets this row render through the identical card as the participant
  inbox, so the two surfaces cannot drift apart visually. Both sets of names descend
  from the retired `conversation_summaries` read table, which is why they look like
  columns.

  `unread_count` and `enrolled_child_names` are pinned to `0` and `[]` and exist for
  that reason alone:

    * **`unread_count`** can never be anything else here. It is derived from
      `Participant.last_read_at`, and the whole point of this surface is that the
      reader has no participant row. The card hides its badge at zero.
    * **`enrolled_child_names`** is the one field genuinely owned by Family and
      Enrollment rather than Messaging, and it was left out of the first cut. The
      card omits its caption when the list is empty, so nothing breaks — an owner
      simply sees slightly less context here than on their own threads.
  """

  @typedoc "One conversation a provider owns but does not participate in."
  @type t :: %__MODULE__{
          conversation_id: String.t(),
          conversation_type: :direct | :program_broadcast,
          provider_id: String.t(),
          program_id: String.t() | nil,
          program_name: String.t() | nil,
          other_participant_name: String.t() | nil,
          staff_member_names: [String.t()],
          latest_message_content: String.t() | nil,
          latest_message_at: DateTime.t() | nil,
          has_attachments: boolean(),
          unread_count: non_neg_integer(),
          enrolled_child_names: [String.t()],
          inserted_at: DateTime.t()
        }

  @enforce_keys [:conversation_id, :conversation_type, :provider_id, :inserted_at]

  defstruct [
    :conversation_id,
    :conversation_type,
    :provider_id,
    :program_id,
    :program_name,
    :other_participant_name,
    :latest_message_content,
    :latest_message_at,
    :inserted_at,
    staff_member_names: [],
    has_attachments: false,
    unread_count: 0,
    enrolled_child_names: []
  ]
end
